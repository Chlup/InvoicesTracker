# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "invoices_tracker/dmg"

class InvoicesTrackerDmgTest < Minitest::Test
  # The file dmgbuild reads for the layout of the disk image window.
  SETTINGS_FILE = File.expand_path("../dmg_settings.py", __dir__)

  # Python that runs the settings file the way dmgbuild does, with the defines it
  # is given as JSON, and prints what the file set as JSON. The module the file
  # imports and the defines are left out, as JSON cannot hold them.
  RUN_SETTINGS = <<~PYTHON
    import json, sys
    namespace = {"defines": json.loads(sys.argv[2])}
    exec(compile(open(sys.argv[1]).read(), sys.argv[1], "exec"), namespace)
    left_out = ("os", "defines")
    print(json.dumps({k: v for k, v in namespace.items() if not k.startswith("__") and k not in left_out}))
  PYTHON

  def test_filename_joins_name_version_and_build
    assert_equal "InvoicesTracker-1.0-1.dmg",
                 InvoicesTracker::Dmg.filename(app_name: "InvoicesTracker", version: "1.0", build: "1")
  end

  def test_filename_turns_spaces_into_hyphens
    assert_equal "Invoices-Tracker-1.2.3-45.dmg",
                 InvoicesTracker::Dmg.filename(app_name: " Invoices  Tracker ", version: "1.2.3", build: "45")
  end

  def test_dmgbuild_command_gives_dmgbuild_the_settings_the_app_and_the_names
    assert_equal ["/v/bin/dmgbuild", "-s", "/r/fastlane/dmg_settings.py", "-D", "app=/s/InvoicesTracker.app",
                  "InvoicesTracker", "/w/x.dmg"],
                 InvoicesTracker::Dmg.dmgbuild_command(
                   dmgbuild: "/v/bin/dmgbuild", settings: "/r/fastlane/dmg_settings.py",
                   app: "/s/InvoicesTracker.app", dmg_path: "/w/x.dmg", volname: "InvoicesTracker"
                 )
  end

  def test_dmgbuild_command_adds_the_volume_icon_only_when_given
    with_icon = InvoicesTracker::Dmg.dmgbuild_command(
      dmgbuild: "d", settings: "s", app: "a", dmg_path: "x", volname: "v", volicon: "/a/AppIcon.icns"
    )
    without_icon = InvoicesTracker::Dmg.dmgbuild_command(
      dmgbuild: "d", settings: "s", app: "a", dmg_path: "x", volname: "v"
    )

    assert_equal ["-D", "volicon=/a/AppIcon.icns"], with_icon[5, 2]
    assert_equal %w[v x], with_icon.last(2)
    assert_equal ["d", "-s", "s", "-D", "app=a", "v", "x"], without_icon
  end

  # The command runs without a shell, so a path with spaces stays one argument.
  def test_dmgbuild_command_keeps_paths_with_spaces_whole
    cmd = InvoicesTracker::Dmg.dmgbuild_command(
      dmgbuild: "/my env/bin/dmgbuild", settings: "/my repo/dmg_settings.py", app: "/my stage/InvoicesTracker.app",
      dmg_path: "/my build/x.dmg", volname: "Invoices Tracker", volicon: "/my stage/Icon Name.icns"
    )

    assert_equal ["/my env/bin/dmgbuild", "-s", "/my repo/dmg_settings.py",
                  "-D", "app=/my stage/InvoicesTracker.app", "-D", "volicon=/my stage/Icon Name.icns",
                  "Invoices Tracker", "/my build/x.dmg"], cmd
  end

  # The layout the image has always had: the window, the icon positions, the
  # link to Applications and the image format.
  def test_the_settings_file_lays_out_the_window_the_icons_and_the_applications_link
    settings = File.read(SETTINGS_FILE)

    [
      "window_rect = ((200, 120), (600, 400))",
      "icon_size = 128",
      "(150, 190)",
      "(450, 190)",
      "'Applications': '/Applications'",
      "format = 'UDZO'"
    ].each { |setting| assert_includes settings, setting }
  end

  def test_the_settings_file_takes_the_app_and_the_volume_icon_from_the_defines_of_the_command
    settings = File.read(SETTINGS_FILE)

    assert_includes settings, "app = defines['app']"
    assert_includes settings, "icon = defines.get('volicon')"
  end

  # The text checks above also pass for a file that does not run, or that names
  # the icons wrongly. So the file runs once, as dmgbuild runs it, with the
  # defines the lane passes.
  def test_the_settings_file_runs_and_lays_out_the_app_it_is_given
    settings = evaluated_settings("app" => "/s/InvoicesTracker.app", "volicon" => "/a/AppIcon.icns")

    assert_equal ["/s/InvoicesTracker.app"], settings["files"]
    assert_equal({ "Applications" => "/Applications" }, settings["symlinks"])
    assert_equal "/a/AppIcon.icns", settings["icon"]
    assert_equal "UDZO", settings["format"]
    assert_equal [[200, 120], [600, 400]], settings["window_rect"]
    assert_equal 128, settings["icon_size"]
    assert_equal({ "InvoicesTracker.app" => [150, 190], "Applications" => [450, 190] }, settings["icon_locations"])
    assert_equal ["InvoicesTracker.app"], settings["hide_extensions"]
    assert_equal [false] * 4, settings.values_at("show_status_bar", "show_toolbar", "show_pathbar", "show_sidebar")
  end

  def test_the_settings_file_leaves_the_volume_icon_unset_when_there_is_none
    assert_nil evaluated_settings("app" => "/s/InvoicesTracker.app")["icon"]
  end

  def test_codesign_command_signs_with_the_given_identity_and_a_secure_timestamp
    assert_equal ["codesign", "--sign", "C0FFEE", "--timestamp", "--force", "/d.dmg"],
                 InvoicesTracker::Dmg.codesign_command(path: "/d.dmg", identity: "C0FFEE")
  end

  # There is deliberately no default: a bare "Developer ID Application" selector
  # would also match another team's certificate in the same keychain.
  def test_codesign_command_has_no_default_identity
    assert_raises(ArgumentError) { InvoicesTracker::Dmg.codesign_command(path: "/d.dmg") }
  end

  private

  # What the settings file sets when it runs with `defines`, as JSON turns it into
  # Ruby: tuples become arrays. The test is skipped on a machine without python3.
  def evaluated_settings(defines)
    skip "python3 is not installed" unless system("command -v python3 > /dev/null 2>&1")

    stdout, stderr, status = Open3.capture3("python3", "-I", "-c", RUN_SETTINGS, SETTINGS_FILE, JSON.generate(defines))
    assert status.success?, "the settings file does not run: #{stderr}"
    JSON.parse(stdout)
  end
end
