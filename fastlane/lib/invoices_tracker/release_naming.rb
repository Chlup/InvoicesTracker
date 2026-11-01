# frozen_string_literal: true

require_relative "release"

module InvoicesTracker
  # The names a release is published under: the git tag, the release title, the
  # address its assets are downloaded from, and the changelog file that goes
  # with the disk image. Pure string building with no I/O, so every name is
  # derived from the version and the build in one place.
  module ReleaseNaming
    module_function

    # The git tag of a release, `v<version>-<build>`, for example `v1.7.0-10`.
    def tag(version:, build:)
      "v#{version}-#{build}"
    end

    # The title the GitHub release shows, for example `InvoicesTracker 1.7.0 (10)`.
    def title(version:, build:)
      "#{Release::APP_NAME} #{version} (#{build})"
    end

    # The address the release's assets are downloaded from. It ends in a slash,
    # so a file name appended to it names one asset of that release.
    def download_prefix(version:, build:)
      "#{Release::RELEASES_URL}/download/#{tag(version: version, build: build)}/"
    end

    # The changelog file published with a disk image: the image's name with
    # `.md` in place of `.dmg`, for example `InvoicesTracker-1.7.0-10.md`.
    def notes_filename(dmg_filename)
      dmg_filename.delete_suffix(".dmg") + ".md"
    end
  end
end
