require "spec_helper"

module Paperclip
  class MyVipsProcessor < Processor
    def make
      basename = File.basename(file.path, File.extname(file.path))
      dst = Paperclip::TempfileFactory.new.generate("#{basename}.png")

      # Use the new vips helper instead of convert
      vips("thumbnail :src :dst 100",
           src: File.expand_path(file.path),
           dst: File.expand_path(dst.path))
      dst
    end
  end
end

describe Paperclip::MyVipsProcessor do
  let(:file) { File.open(fixture_file("50x50.png")) }
  let(:options) { {} }
  let(:attachment) { double }
  let(:processor) { Paperclip::MyVipsProcessor.new(file, options, attachment) }

  subject { processor.make }

  it "processes the image using vips helper" do
    expect(subject).to respond_to(:path)
    expect(File.exist?(subject.path)).to be true

    # Check width using vipsheader
    require "shellwords"
    width = `vipsheader -f width #{Shellwords.escape(subject.path)}`.strip.to_i
    expect(width).to eq(100)
  end

  it "calls the vips command" do
    expect(Paperclip).to receive(:run).with(
      "vips",
      "thumbnail :src :dst 100",
      hash_including(:src, :dst),
    )
    processor.make
  end
end
