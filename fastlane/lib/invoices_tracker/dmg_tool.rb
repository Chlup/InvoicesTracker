# frozen_string_literal: true

require "digest"

module InvoicesTracker
  # The Python environment that holds dmgbuild, the tool that makes the disk
  # image. dmgbuild is not a Homebrew formula, so it is installed with pip into
  # a virtual environment of its own in the build folder, never into a Python
  # that other things use. fastlane/requirements-dmg.txt pins dmgbuild and the
  # packages it needs to exact versions with the hashes of their files, so a
  # local build and a CI build install the very same files. The environment
  # keeps a stamp of the requirements it was installed from, and the lane makes
  # it again when they change. Pure: the paths, the commands and the check
  # whether the environment is current are here, and callers run the commands
  # and read and write the stamp file.
  module DmgTool
    module_function

    # The virtual environment of the repository at `repo_root`: build/dmg-env.
    # It is next to build/release, not inside it, because the lane deletes
    # build/release at the start of every run and the environment should outlast
    # the runs.
    def venv_dir(repo_root)
      File.join(repo_root, "build", "dmg-env")
    end

    # The dmgbuild executable of the environment `venv_dir`.
    def dmgbuild_path(venv_dir)
      File.join(venv_dir, "bin", "dmgbuild")
    end

    # The file in the environment `venv_dir` that holds the stamp: the digest of
    # the requirements the environment was installed from. It is inside the
    # environment, so deleting the environment deletes the stamp with it.
    def stamp_path(venv_dir)
      File.join(venv_dir, "requirements.sha256")
    end

    # The commands that make the environment `venv_dir` with `python` and
    # install the packages of the requirements file `requirements` into it, each
    # an array to run without a shell. pip is told to refuse any package whose
    # hash is not in the file, and not to ask PyPI whether it is out of date.
    def setup_commands(python:, venv_dir:, requirements:)
      [
        [python, "-m", "venv", venv_dir],
        [File.join(venv_dir, "bin", "pip"), "install", "--disable-pip-version-check", "--require-hashes",
         "-r", requirements]
      ]
    end

    # The stamp of an environment installed from `requirements_text`, the text of
    # the requirements file: its SHA-256 in lowercase hex.
    def requirements_digest(requirements_text)
      Digest::SHA256.hexdigest(requirements_text)
    end

    # Whether an environment whose stamp file holds `stamp_text` (nil when there
    # is no stamp file) was installed from `requirements_text`, the text of the
    # requirements file as it is now. True only when the stamp is exactly the
    # digest of those requirements: a missing, empty or damaged stamp, and one of
    # other requirements, all mean the environment has to be made again.
    def up_to_date?(stamp_text, requirements_text)
      stamp_text == requirements_digest(requirements_text)
    end
  end
end
