require "spec_helper"

describe Paperclip::Thumbnail do
  describe "#parse_loader_options" do
    let(:file) { File.new(fixture_file("5k.png"), "rb") }
    let(:thumb) { Paperclip::Thumbnail.new(file, geometry: "50x50") }

    after { file.close }

    it "correctly parses positive numeric values" do
      options = "-density 300"
      result = thumb.send(:parse_loader_options, options)
      expect(result).to eq({ density: "300" })
    end

    it "correctly parses negative numeric values" do
      # Some hypothetical loader option that might take a negative value
      options = "-something -90"
      result = thumb.send(:parse_loader_options, options)
      expect(result).to eq({ something: "-90" })
    end

    it "still treats non-numeric tokens starting with - as new options" do
      options = "-density 300 -strip"
      result = thumb.send(:parse_loader_options, options)
      expect(result).to eq({ density: "300", strip: true })
    end
  end
end
