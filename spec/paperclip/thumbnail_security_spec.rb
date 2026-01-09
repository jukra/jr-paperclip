require "spec_helper"

describe Paperclip::Thumbnail do
  context "Security" do
    old_backend = Paperclip.options[:backend]

    before do
      @file = File.new(fixture_file("5k.png"), "rb")
      @attachment = double("Attachment", options: {})
      Paperclip.options[:backend] = :image_magick
    end

    after do
      @file.close
      Paperclip.options[:backend] = old_backend
    end

    it "allows safe convert options" do
      thumb = Paperclip::Thumbnail.new(@file, { geometry: "100x100", convert_options: "-strip" }, @attachment)

      expect(Paperclip).to_not receive(:log).with(/Warning: Option strip is not allowed/)
      thumb.make
    end

    it "blocks unsafe convert options" do
      # -write is not in the ALLOWED_IMAGEMAGICK_OPTIONS list
      thumb = Paperclip::Thumbnail.new(@file, { geometry: "100x100", convert_options: "-write /tmp/hacked.png" },
                                       @attachment)

      expect(Paperclip).to receive(:log).with("Warning: Option write is not allowed.")
      thumb.make
    end

    it "allows options with underscores in the whitelist when passed with hyphens" do
      # 'auto_orient' is in the list. User passes '-auto-orient'.
      thumb = Paperclip::Thumbnail.new(@file, { geometry: "100x100", convert_options: "-auto-orient" }, @attachment)

      expect(Paperclip).to_not receive(:log).with(/Warning: Option auto-orient is not allowed/)
      thumb.make
    end
  end
end
