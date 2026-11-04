# frozen_string_literal: true

require "spec_helper"
require "mini_magick"
require "tempfile"

describe Paperclip::ImageMagickPolicy do
  let(:policy_directory) { described_class::POLICY_DIRECTORY }

  it "prepends the policy and preserves the caller's configuration path" do
    allow(ENV).to receive(:[]).with("MAGICK_CONFIGURE_PATH").and_return("/process/policy")

    environment = described_class.command_environment("MAGICK_CONFIGURE_PATH" => "/caller/policy")

    expect(environment["MAGICK_CONFIGURE_PATH"].split(File::PATH_SEPARATOR)).to eq(
      [policy_directory, "/caller/policy"],
    )
  end

  it "preserves Terrapin's global path before the process path" do
    allow(ENV).to receive(:[]).with("MAGICK_CONFIGURE_PATH").and_return("/process/policy")

    environment = described_class.command_environment({}, "/terrapin/policy")

    expect(environment["MAGICK_CONFIGURE_PATH"].split(File::PATH_SEPARATOR)).to eq(
      [policy_directory, "/terrapin/policy"],
    )
  end

  it "preserves the process configuration path when no caller path is set" do
    allow(ENV).to receive(:[]).with("MAGICK_CONFIGURE_PATH").and_return("/process/policy")

    environment = described_class.command_environment

    expect(environment["MAGICK_CONFIGURE_PATH"].split(File::PATH_SEPARATOR)).to eq(
      [policy_directory, "/process/policy"],
    )
  end

  it "rejects GraphicsMagick because it does not use ImageMagick's policy" do
    original = MiniMagick.graphicsmagick
    MiniMagick.graphicsmagick = true

    expect { described_class.apply_to_mini_magick! }.to raise_error(/requires MiniMagick to use ImageMagick/)
  ensure
    MiniMagick.graphicsmagick = original
  end

  it "rejects CLI prefixes that could clear the policy environment" do
    original = MiniMagick.cli_prefix
    MiniMagick.cli_prefix = ["env", "-i"]

    expect { described_class.apply_to_mini_magick! }.to raise_error(/without a CLI prefix/)
  ensure
    MiniMagick.cli_prefix = original
  end

  it "applies the policy to direct ImageMagick commands" do
    policies = Paperclip.run("identify", "-list policy")

    expect(policies).to include(described_class::POLICY_PATH)
    expect(policies).to match(/Policy: Coder\s+rights: None\s+pattern: MSL/i)
  end

  it "applies the policy to MiniMagick commands" do
    described_class.apply_to_mini_magick!
    policies = MiniMagick.identify { |command| command << "-list" << "policy" }

    expect(MiniMagick.cli_env["MAGICK_CONFIGURE_PATH"].split(File::PATH_SEPARATOR).first).to eq(policy_directory)
    expect(policies).to include(described_class::POLICY_PATH)
    expect(policies).to match(/Policy: Coder\s+rights: None\s+pattern: MSL/i)
  end

  it "rejects MSL files through both command paths" do
    Tempfile.create(["paperclip-policy", ".msl"]) do |file|
      file.write('<image><read filename="/tmp/unused.png"/></image>')
      file.flush

      expect { Paperclip.run("identify", "msl:#{file.path}") }.
        to raise_error(Terrapin::ExitStatusError, /security policy.*MSL/)

      described_class.apply_to_mini_magick!
      expect { MiniMagick.identify { |command| command << "msl:#{file.path}" } }.
        to raise_error(MiniMagick::Error, /security policy.*MSL/)
    end
  end

  it "keeps ordinary PNG thumbnailing available" do
    file = File.open(fixture_file("5k.png"), "rb")
    thumbnail = Paperclip::Thumbnail.new(file, geometry: "100x100")

    expect(thumbnail.make.size).to be_positive
  ensure
    file&.close
  end
end
