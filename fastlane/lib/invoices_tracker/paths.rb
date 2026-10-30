# frozen_string_literal: true

require_relative "dmg"
require_relative "release"

module InvoicesTracker
  # Where a release build reads and writes, as absolute paths.
  #
  # fastlane changes into other directories around its actions, so a relative
  # path can resolve somewhere other than intended. Anchoring every path to the
  # repository root makes them independent of the working directory.
  module Paths
    module_function

    # `repo_root` must be an absolute path.
    #
    # The tests and the release build keep separate DerivedData directories,
    # both inside the repository and never in Xcode's own.
    #
    # Everything a run produces except the finished DMG lives under `work_dir`.
    # The DMG is built, signed, notarized and verified at `work_dmg`, and only
    # then placed at `final_dmg`, which is outside `work_dir`: a run that fails
    # on the way never leaves a finished-looking file at the final path.
    def resolve(repo_root:, version:, build:)
      paths = base(repo_root: repo_root)
      dmg_name = Dmg.filename(app_name: Release::APP_NAME, version: version, build: build)

      paths.merge(
        work_dmg: File.join(paths[:work_dir], dmg_name),
        final_dmg: File.join(build_dir(repo_root), dmg_name)
      ).freeze
    end

    # Every path of `resolve` that does not depend on the version: all but the
    # DMGs. The version is read from the project, through some of these paths,
    # before it is known.
    def base(repo_root:)
      work_dir = File.join(build_dir(repo_root), "release")
      export_dir = File.join(work_dir, "export")

      {
        project: File.join(repo_root, Release::PROJECT),
        test_derived_data: File.join(repo_root, "DerivedData"),
        derived_data: File.join(build_dir(repo_root), "DerivedData"),
        work_dir: work_dir,
        archive: File.join(work_dir, "#{Release::APP_NAME}.xcarchive"),
        export_dir: export_dir,
        app: File.join(export_dir, "#{Release::APP_NAME}.app"),
        staging: File.join(work_dir, "dmg-staging")
      }.freeze
    end

    def build_dir(repo_root)
      File.join(repo_root, "build")
    end
    private_class_method :build_dir
  end
end
