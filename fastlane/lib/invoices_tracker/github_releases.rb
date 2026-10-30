# frozen_string_literal: true

require "json"
require_relative "deploy_preflight"

module InvoicesTracker
  # Asks GitHub, through the `gh` command-line tool, what a deploy has to know
  # about the releases already published: whether the git tag of a release
  # exists, and which release is the Latest one, with the text of its update
  # feed. `gh` is a callable that is passed in, so a test never reaches the
  # network. It takes the arguments of one call, an array, and gives back what
  # the tool printed and whether it succeeded, `[stdout, stderr, success]`. The
  # workflow passes one that runs the real tool, which signs in with the token
  # in its environment, so no token passes through here. A call that fails is
  # reported by its arguments and the HTTP status gh printed for it, if any, and
  # by nothing else of its output, which may hold a token or the body of the
  # response. The repository and the tag go into the addresses as they are:
  # callers pass names that were checked before. GitHub answers 404 for a
  # repository that does not exist or that the token cannot see, as it does for
  # a tag or a release that is not there, so a wrong repository reads as
  # nothing published.
  module GitHubReleases
    # The name of the update feed among the assets of a release.
    APPCAST_NAME = "appcast.xml"

    # What gh prints on stderr when GitHub answers 404 Not Found, for example
    # `gh: Not Found (HTTP 404)`.
    NOT_FOUND = "HTTP 404"

    # The HTTP status in what gh prints on stderr when GitHub refuses a request.
    HTTP_STATUS = /HTTP (\d{3})/

    module_function

    # Whether the git tag `tag` exists in `repository`, given as `owner/name`.
    # The question is for the ref of the tag, which GitHub answers with 404 when
    # there is no such tag. Raises RuntimeError, naming the call, when the
    # question fails with any other status.
    def tag_exists?(repository:, tag:, gh:)
      !call_gh(gh, ["api", "repos/#{repository}/git/ref/tags/#{tag}"], allow_missing: true).nil?
    end

    # The Latest release of `repository`, given as `owner/name`: the one GitHub
    # labels so, which the feed address `releases/latest/download/appcast.xml`
    # resolves to. A DeployPreflight::LatestRelease with its tag and the text of
    # its `appcast.xml` asset as gh printed it, nil when the release has no such
    # asset. Gives nil when there is no Latest release: GitHub answers 404 while
    # nothing is published.
    #
    # Raises RuntimeError, naming the call and quoting nothing of the answer,
    # when the question fails with any other status, when the answer is no
    # release, and when the appcast that the release lists cannot be
    # downloaded. A listed appcast that is gone is an error, not a release that
    # has none.
    def latest(repository:, gh:)
      args = ["api", "repos/#{repository}/releases/latest"]
      body = call_gh(gh, args, allow_missing: true)
      return if body.nil?

      tag, appcast_id = read_release(args, body)
      appcast_xml = appcast_id && download_asset(repository, appcast_id, gh)
      DeployPreflight::LatestRelease.new(tag: tag, appcast_xml: appcast_xml)
    end

    # The text of the asset of `repository` whose id is `id`. The header asks
    # for the file itself: without it GitHub answers with a description of the
    # asset. Any failure raises RuntimeError, a 404 included: the id comes from
    # the release, which lists the asset.
    def download_asset(repository, id, gh)
      call_gh(gh, ["api", "-H", "Accept: application/octet-stream", "repos/#{repository}/releases/assets/#{id}"])
    end
    private_class_method :download_asset

    # Runs the gh call `args` and gives what it printed on stdout, as UTF-8 text.
    # The label of the string that gh's output arrives in is not trusted: Open3
    # puts the locale of the process on it, which may be US-ASCII, and the JSON
    # parser refuses that label once the notes of a release have a letter that
    # is not ASCII. What gh prints is UTF-8, the JSON of GitHub and the XML of
    # Sparkle alike.
    #
    # When the call failed, gives nil if `allow_missing` is set and GitHub
    # answered 404 Not Found. Any other failure raises RuntimeError with the
    # call, and the HTTP status when gh printed one, and nothing else of what
    # gh printed.
    def call_gh(gh, args, allow_missing: false)
      stdout, stderr, success = gh.call(args)
      return stdout.to_s.dup.force_encoding(Encoding::UTF_8) if success

      # Only ASCII is looked for in the message, so it is matched as bytes: a
      # letter that does not fit the label of the string would make a pattern
      # refuse to match it, and the error would not be the one for the call.
      message = stderr.to_s.b
      return nil if allow_missing && message.include?(NOT_FOUND)

      status = message[HTTP_STATUS, 1]
      suffix = status ? " (HTTP #{status})" : ""
      raise "#{command_line(args)} failed#{suffix}"
    end
    private_class_method :call_gh

    # The call `args` as a command line, to name it in a message.
    def command_line(args)
      ["gh", *args].join(" ")
    end
    private_class_method :command_line

    # The tag of the release in `body`, the JSON that gh printed for the call
    # `args`, and the id of its `appcast.xml` asset, nil when it has none.
    # Raises RuntimeError, naming the call and quoting nothing of the body, when
    # the body is no release or when the id of the appcast is not a whole
    # number: it goes into the address of the download.
    def read_release(args, body)
      release = parse_json(body)
      if release?(release)
        appcast = release["assets"].find { |asset| asset["name"] == APPCAST_NAME }
        return [release["tag_name"], nil] if appcast.nil?
        return [release["tag_name"], appcast["id"]] if appcast["id"].is_a?(Integer)
      end

      raise "#{command_line(args)} printed something that is not a release"
    end
    private_class_method :read_release

    # The value of the JSON text `text`, nil when it is not JSON. The message of
    # the parser is dropped: it quotes the text it could not read.
    def parse_json(text)
      JSON.parse(text)
    rescue JSON::ParserError
      nil
    end
    private_class_method :parse_json

    # Whether `value`, read from JSON, has what a release has that is used here:
    # a `tag_name` that is text and not blank, and a list of `assets`, each of
    # them an object.
    def release?(value)
      return false unless value.is_a?(Hash)

      tag = value["tag_name"]
      assets = value["assets"]
      tag.is_a?(String) && !tag.strip.empty? && assets.is_a?(Array) && assets.all?(Hash)
    end
    private_class_method :release?
  end
end
