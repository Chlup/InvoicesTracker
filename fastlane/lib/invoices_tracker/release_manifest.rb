# frozen_string_literal: true

require "json"
require_relative "release_naming"

module InvoicesTracker
  # The metadata of a release that is about to be published, `release.json`.
  # The build job writes it into the feed folder next to the files it
  # describes: the disk image, the update feed and the release notes. The
  # publish job, which runs on another machine, reads it to check those files
  # by their SHA-256 and to create the release, and compares the Latest release
  # it finds with the one the build saw. Every value is text. Pure.
  module ReleaseManifest
    # The name of the metadata file in the feed folder.
    FILE_NAME = "release.json"

    # The name of the release notes in the feed folder.
    NOTES_FILE_NAME = "release-notes.md"

    module_function

    # The metadata, in this order: the version and the build, the tag and the
    # title they give, the commit the release is built from (the tag will point
    # at it), the disk image's file name and SHA-256, the feed's SHA-256, the
    # file name of the notes, and the tag of the Latest release when the feed
    # was made, `latest_tag`, which is an empty string when nothing was
    # published yet.
    def contents(version:, build:, commit:, dmg:, dmg_sha256:, appcast_sha256:, latest_tag:)
      {
        "version" => version,
        "build" => build,
        "tag" => ReleaseNaming.tag(version: version, build: build),
        "title" => ReleaseNaming.title(version: version, build: build),
        "commit" => commit,
        "dmg" => dmg,
        "dmg_sha256" => dmg_sha256,
        "appcast_sha256" => appcast_sha256,
        "notes" => NOTES_FILE_NAME,
        "latest_tag_seen" => latest_tag.to_s
      }
    end

    # The text of the file: `contents` as indented JSON, ending with a line
    # break.
    def json(contents)
      "#{JSON.pretty_generate(contents)}\n"
    end
  end
end
