# frozen_string_literal: true

require "minitest/autorun"
require "invoices_tracker/dmg_tool"

class InvoicesTrackerDmgToolTest < Minitest::Test
  REQUIREMENTS_FILE = File.expand_path("../requirements-dmg.txt", __dir__)

  # The SHA-256 of the three characters "abc", from the published test vectors.
  ABC_DIGEST = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

  def test_the_environment_is_in_the_build_folder_of_the_repository
    assert_equal "/r/build/dmg-env", InvoicesTracker::DmgTool.venv_dir("/r")
  end

  def test_dmgbuild_is_in_the_bin_folder_of_the_environment
    assert_equal "/r/build/dmg-env/bin/dmgbuild", InvoicesTracker::DmgTool.dmgbuild_path("/r/build/dmg-env")
  end

  def test_the_stamp_is_a_file_in_the_environment
    assert_equal "/r/build/dmg-env/requirements.sha256", InvoicesTracker::DmgTool.stamp_path("/r/build/dmg-env")
  end

  def test_setup_makes_the_environment_and_installs_the_requirements_by_their_hashes
    assert_equal [["python3", "-m", "venv", "/r/build/dmg-env"],
                  ["/r/build/dmg-env/bin/pip", "install", "--disable-pip-version-check", "--require-hashes",
                   "-r", "/r/fastlane/requirements-dmg.txt"]],
                 InvoicesTracker::DmgTool.setup_commands(
                   python: "python3", venv_dir: "/r/build/dmg-env", requirements: "/r/fastlane/requirements-dmg.txt"
                 )
  end

  def test_setup_makes_the_environment_with_the_python_it_is_given
    commands = InvoicesTracker::DmgTool.setup_commands(
      python: "/opt/python/bin/python3.12", venv_dir: "/e", requirements: "/q.txt"
    )

    assert_equal ["/opt/python/bin/python3.12", "-m", "venv", "/e"], commands.first
    assert_equal ["/e/bin/pip"], commands.last.first(1)
  end

  def test_the_digest_of_the_requirements_is_their_sha256_in_hex
    assert_equal ABC_DIGEST, InvoicesTracker::DmgTool.requirements_digest("abc")
  end

  def test_an_environment_is_up_to_date_when_its_stamp_is_the_digest_of_the_requirements
    assert InvoicesTracker::DmgTool.up_to_date?(ABC_DIGEST, "abc")
    assert InvoicesTracker::DmgTool.up_to_date?(InvoicesTracker::DmgTool.requirements_digest("a\nb\n"), "a\nb\n")
  end

  def test_an_environment_without_a_stamp_is_stale
    refute InvoicesTracker::DmgTool.up_to_date?(nil, "abc")
    refute InvoicesTracker::DmgTool.up_to_date?("", "abc")
  end

  def test_an_environment_is_stale_when_the_requirements_changed_since_the_stamp
    refute InvoicesTracker::DmgTool.up_to_date?(ABC_DIGEST, "abc\n")
    refute InvoicesTracker::DmgTool.up_to_date?(ABC_DIGEST, "")
  end

  def test_a_stamp_that_is_not_the_digest_of_the_requirements_is_stale
    refute InvoicesTracker::DmgTool.up_to_date?("#{ABC_DIGEST}-old", "abc")
    refute InvoicesTracker::DmgTool.up_to_date?(ABC_DIGEST[0, 63], "abc")
    refute InvoicesTracker::DmgTool.up_to_date?("abc", "abc")
  end

  # pip's --require-hashes mode needs every package pinned with == and carrying a
  # hash, the packages dmgbuild needs as well as dmgbuild itself.
  def test_the_requirements_pin_dmgbuild_and_what_it_needs_with_one_hash_each
    pins = requirement_lines.to_h do |line|
      requirement, *hashes = line.split
      assert_equal 1, hashes.size, line
      assert_match(/\A--hash=sha256:\h{64}\z/, hashes.first, line)
      requirement.split("==")
    end

    assert_equal({ "dmgbuild" => "1.6.7", "ds_store" => "1.3.3", "mac_alias" => "2.2.3" }, pins)
  end

  private

  # The requirements as pip reads them: a backslash joins a line to the next one,
  # and a comment runs to the end of its line.
  def requirement_lines
    File.read(REQUIREMENTS_FILE).gsub("\\\n", " ").lines.map { |line| line.sub(/#.*/, "").strip }.reject(&:empty?)
  end
end
