# frozen_string_literal: true

require "minitest/autorun"
require "invoices_tracker/paths"

class InvoicesTrackerPathsTest < Minitest::Test
  def paths
    InvoicesTracker::Paths.resolve(repo_root: "/r", version: "1.0", build: "1")
  end

  def test_paths_are_absolute_and_under_the_repository
    expected = {
      project: "/r/InvoicesTracker.xcodeproj",
      test_derived_data: "/r/DerivedData",
      derived_data: "/r/build/DerivedData",
      work_dir: "/r/build/release",
      archive: "/r/build/release/InvoicesTracker.xcarchive",
      export_dir: "/r/build/release/export",
      app: "/r/build/release/export/InvoicesTracker.app",
      staging: "/r/build/release/dmg-staging",
      work_dmg: "/r/build/release/InvoicesTracker-1.0-1.dmg",
      final_dmg: "/r/build/InvoicesTracker-1.0-1.dmg"
    }
    resolved = paths

    assert_equal expected.keys.sort, resolved.keys.sort
    expected.each do |key, path|
      assert_equal path, resolved.fetch(key), "#{key} path"
      assert File.absolute_path?(resolved.fetch(key)), "#{key} must be absolute"
      assert resolved.fetch(key).start_with?("/r/"), "#{key} must be under the repository"
    end
  end

  def test_the_final_dmg_is_outside_the_work_dir
    resolved = paths

    refute resolved[:final_dmg].start_with?(resolved[:work_dir]), "the finished DMG must not live in the work dir"
    assert resolved[:work_dmg].start_with?(resolved[:work_dir]), "the DMG under construction lives in the work dir"
  end

  def test_the_result_is_frozen
    assert_predicate paths, :frozen?
  end

  # The version lookup needs the project and the release DerivedData before the
  # version is known, so these paths come without one.
  def test_the_base_holds_every_path_that_does_not_depend_on_the_version
    expected = {
      project: "/r/InvoicesTracker.xcodeproj",
      test_derived_data: "/r/DerivedData",
      derived_data: "/r/build/DerivedData",
      work_dir: "/r/build/release",
      archive: "/r/build/release/InvoicesTracker.xcarchive",
      export_dir: "/r/build/release/export",
      app: "/r/build/release/export/InvoicesTracker.app",
      staging: "/r/build/release/dmg-staging"
    }

    assert_equal expected, InvoicesTracker::Paths.base(repo_root: "/r")
  end

  def test_resolve_builds_on_the_base_and_adds_the_dmgs
    base = InvoicesTracker::Paths.base(repo_root: "/r")
    resolved = paths

    base.each { |key, path| assert_equal path, resolved.fetch(key), "#{key} path" }
    assert_equal base.keys + %i[work_dmg final_dmg], resolved.keys
  end

  def test_the_base_is_frozen
    assert_predicate InvoicesTracker::Paths.base(repo_root: "/r"), :frozen?
  end

  def test_the_root_the_version_and_the_build_all_flow_into_the_paths
    resolved = InvoicesTracker::Paths.resolve(repo_root: "/work/repo", version: "2.1.0", build: "37")

    assert_equal "/work/repo/InvoicesTracker.xcodeproj", resolved[:project]
    assert_equal "/work/repo/build/release/InvoicesTracker-2.1.0-37.dmg", resolved[:work_dmg]
    assert_equal "/work/repo/build/InvoicesTracker-2.1.0-37.dmg", resolved[:final_dmg]
  end
end
