# frozen_string_literal: true

require_relative "release"
require_relative "release_naming"
require_relative "release_notes"
require_relative "sparkle"

module InvoicesTracker
  # Turns the facts gathered before a deploy, a release that is published and
  # not a dry run that only builds, into one ordered list of problems, so
  # everything that is wrong shows at once instead of one thing per run. A
  # published release is what installed apps update to: it must not reuse a tag
  # or a build, must leave the update feed in place, and must be signed with the
  # key those apps trust. No I/O: the workflow gathers the facts from GitHub and
  # from the app's Info.plist, and acts on the verdict. The typed numbers
  # themselves are checked by BuildSettings.
  module DeployPreflight
    # The release GitHub shows as the Latest one, which the feed address
    # `releases/latest/download/appcast.xml` resolves to:
    # - `tag`: its git tag.
    # - `appcast_xml`: the text of its `appcast.xml` asset, nil when it has none.
    LatestRelease = Struct.new(:tag, :appcast_xml, keyword_init: true)

    # What the workflow found out:
    # - `version`, `build`: the typed numbers, trimmed. BuildSettings checks that
    #   they are well formed and the branch's own.
    # - `changelog`: the typed release notes.
    # - `tag_exists`: whether the git tag of this release is on GitHub already.
    # - `latest_release`: the LatestRelease, nil when nothing is published yet.
    # - `workflow_changes`: the paths of the workflow files that the commit
    #   being deployed adds or changes compared with the default branch, as
    #   GitHubReleases.workflow_changes lists them. Empty or nil when there are
    #   none, and when GitHub could not tell: that problem is reported where the
    #   question was asked.
    # - `info_plist`: the Sparkle settings of the app's Info.plist as a Hash, nil
    #   when they could not be read.
    # - `sparkle_private_key`: the SPARKLE_PRIVATE_KEY secret, nil when it is not
    #   set. It is a secret, so the facts print without it.
    Facts = Struct.new(
      :version, :build, :changelog, :tag_exists, :latest_release, :workflow_changes, :info_plist, :sparkle_private_key,
      keyword_init: true
    ) do
      # The facts as text, without the private key: `Struct#inspect` would print
      # it, and a log must never show it, in a debug line or a failed assertion
      # alike. Whether a key is set still shows.
      def inspect
        fields = members.map do |member|
          secret = member == :sparkle_private_key && !self[member].nil?
          "#{member}=#{secret ? '[redacted]' : self[member].inspect}"
        end
        "#<struct #{self.class.name} #{fields.join(', ')}>"
      end

      alias_method :to_s, :inspect

      # `pp` prints a struct field by field, not through `inspect`.
      def pretty_print(printer)
        printer.text(inspect)
      end
    end

    module_function

    # Why the deploy must not go on, one sentence each, in the order of the
    # checks: the changelog, the tag, the Latest release, the workflow files of
    # the branch, the feed address of the app, the private key, the public key
    # of the app. Empty when it may go on. A check that depends on a fact that
    # could not be had is left out: an Info.plist that cannot be read says
    # nothing about the feed address or the public key, and a private key that
    # cannot be used has no public key to compare with.
    def errors(facts)
      plist = facts.info_plist
      private_key = facts.sparkle_private_key
      public_key = derive_public_key(private_key)

      found = []
      found.concat(ReleaseNotes.errors(facts.changelog, deploy: true))
      found.concat(tag_errors(facts))
      found.concat(latest_release_errors(facts))
      found.concat(workflow_errors(facts))
      if plist
        found.concat(feed_url_errors(plist))
      else
        found << "the app's Info.plist cannot be read — does the branch have Sparkle?"
      end
      found.concat(private_key_errors(private_key, public_key))
      found.concat(public_key_errors(plist, public_key)) if plist
      found
    end

    # The problem with the tag of this release, if it exists already: a release
    # is named after its tag, which must be a new one.
    def tag_errors(facts)
      return [] unless facts.tag_exists

      tag = ReleaseNaming.tag(version: facts.version, build: facts.build)
      ["the release #{tag} already exists — choose a new build number"]
    end
    private_class_method :tag_errors

    # The problems with the Latest release, which the app's feed address
    # resolves to. It must carry the feed, as every release the workflow
    # publishes does, and the build being deployed must be higher than its
    # newest one, since Sparkle offers an update only for a higher build. With
    # no release published there is nothing to check. A typed build that is not
    # a number has nothing to compare: BuildSettings reports it.
    def latest_release_errors(facts)
      latest = facts.latest_release
      return [] unless latest

      if latest.appcast_xml.nil?
        return ["the Latest release #{latest.tag} has no appcast.xml — " \
                "only the release workflow may publish releases"]
      end

      newest = Sparkle.latest_build(latest.appcast_xml)
      return ["the Latest release #{latest.tag} has an appcast.xml without a build"] unless newest

      build = Integer(facts.build.to_s, 10, exception: false)
      return [] if build.nil? || build > newest

      ["build #{facts.build} is not higher than #{newest}, the newest published build"]
    end
    private_class_method :latest_release_errors

    # The problem with the workflow files of the branch, if it adds or changes
    # any compared with the default branch. GitHub does not let the token of the
    # workflow publish a release of such a commit, so the deploy stops here,
    # before anything is built, and not when the release is published. The
    # paths are named in order. With none, or no list at all, there is nothing
    # to report.
    def workflow_errors(facts)
      paths = facts.workflow_changes
      return [] if paths.nil? || paths.empty?

      ["the branch adds or changes #{paths.sort.join(', ')} compared with the default branch — " \
       "GitHub would refuse to publish the release; merge the default branch into it, " \
       "or land the workflow change there first"]
    end
    private_class_method :workflow_errors

    # The problem with the feed address of the app, if it is not the
    # repository's: apps installed already look for their updates there.
    def feed_url_errors(plist)
      feed_url = plist["SUFeedURL"].to_s
      return [] if feed_url == Release::FEED_URL

      ["SUFeedURL is #{feed_url.empty? ? 'missing' : feed_url}, not #{Release::FEED_URL}"]
    end
    private_class_method :feed_url_errors

    # The public key of a private key, nil when it cannot be derived: the secret
    # is not set, or is not a Sparkle private key.
    def derive_public_key(private_key)
      Sparkle.public_key_for(private_key)
    rescue ArgumentError
      nil
    end
    private_class_method :derive_public_key

    # The problem with the SPARKLE_PRIVATE_KEY secret, if its public key could
    # not be derived. A secret that is blank, whitespace around a key being
    # insignificant, is not set. The messages never quote the secret.
    def private_key_errors(private_key, public_key)
      return [] if public_key
      return ["SPARKLE_PRIVATE_KEY is not set"] if private_key.to_s.strip.empty?

      ["SPARKLE_PRIVATE_KEY is not a Sparkle private key"]
    end
    private_class_method :private_key_errors

    # The problems with the SUPublicEDKey of the app. It must be there, and it
    # must belong to the private key (`public_key`, nil when that cannot be
    # used and there is nothing to compare): an installed app applies an update
    # only when it is signed with the key the app carries.
    def public_key_errors(plist, public_key)
      app_key = plist["SUPublicEDKey"].to_s
      return ["the app has no SUPublicEDKey — does the branch have Sparkle?"] if app_key.empty?
      return [] if public_key.nil? || app_key == public_key

      ["SUPublicEDKey does not match SPARKLE_PRIVATE_KEY — installed apps would reject this update"]
    end
    private_class_method :public_key_errors
  end
end
