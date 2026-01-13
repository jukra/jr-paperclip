require "spec_helper"

describe Paperclip::Helpers do
  describe ".imagemagick7?" do
    before do
      if Paperclip.instance_variable_defined?(:@imagemagick7)
        Paperclip.send(:remove_instance_variable, :@imagemagick7)
      end
    end

    after do
      if Paperclip.instance_variable_defined?(:@imagemagick7)
        Paperclip.send(:remove_instance_variable, :@imagemagick7)
      end
    end

    it "returns true if magick command is found" do
      allow(Paperclip).to receive(:which).with("magick").and_return("/usr/bin/magick")
      expect(Paperclip.imagemagick7?).to be true
    end

    it "returns false if magick command is not found" do
      allow(Paperclip).to receive(:which).with("magick").and_return(nil)
      expect(Paperclip.imagemagick7?).to be false
    end

    it "caches the result" do
      expect(Paperclip).to receive(:which).with("magick").once.and_return("/usr/bin/magick")
      Paperclip.imagemagick7?
      Paperclip.imagemagick7?
    end
  end

  describe ".which" do
    it "finds an executable in the PATH" do
      allow(ENV).to receive(:[]).with("PATH").and_return("/usr/bin:/bin")
      allow(ENV).to receive(:[]).with("PATHEXT").and_return(nil)
      allow(File).to receive(:executable?).with("/usr/bin/ruby").and_return(true)
      expect(Paperclip.which("ruby")).to eq("/usr/bin/ruby")
    end

    it "returns nil if executable is not found" do
      allow(ENV).to receive(:[]).with("PATH").and_return("/usr/bin:/bin")
      allow(ENV).to receive(:[]).with("PATHEXT").and_return(nil)
      allow(File).to receive(:executable?).and_return(false)
      expect(Paperclip.which("nonexistent")).to be_nil
    end
  end
end
