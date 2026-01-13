require "spec_helper"

describe Paperclip::Processor do
  it "instantiates and call #make when sent #make to the class" do
    processor = double
    expect(processor).to receive(:make)
    expect(Paperclip::Processor).to receive(:new).with(:one, :two, :three).and_return(processor)
    Paperclip::Processor.make(:one, :two, :three)
  end

  context "Calling #convert" do
    it "runs the convert command with Terrapin" do
      Paperclip.options[:log_command] = false
      allow(Paperclip).to receive(:imagemagick7?).and_return(false)
      Paperclip.options[:is_windows] = false
      expect(Terrapin::CommandLine).to receive(:new).with("convert", "stuff", {}).and_return(double(run: nil))
      Paperclip::Processor.new("filename").convert("stuff")
    end

    it "runs the magick convert command when ImageMagick 7 is present" do
      Paperclip.options[:log_command] = false
      allow(Paperclip).to receive(:imagemagick7?).and_return(true)
      expect(Terrapin::CommandLine).to receive(:new).with("magick", "stuff", {}).and_return(double(run: nil))
      Paperclip::Processor.new("filename").convert("stuff")
    end
  end

  context "Calling #identify" do
    it "runs the identify command" do
      Paperclip.options[:log_command] = false
      allow(Paperclip).to receive(:imagemagick7?).and_return(false)
      Paperclip.options[:is_windows] = false
      expect(Terrapin::CommandLine).to receive(:new).with("identify", "stuff", {}).and_return(double(run: nil))
      Paperclip::Processor.new("filename").identify("stuff")
    end

    it "runs the magick identify command when ImageMagick 7 is present" do
      Paperclip.options[:log_command] = false
      allow(Paperclip).to receive(:imagemagick7?).and_return(true)
      expect(Terrapin::CommandLine).to receive(:new).with("magick identify", "stuff", {}).and_return(double(run: nil))
      Paperclip::Processor.new("filename").identify("stuff")
    end
  end

  context "Calling #vips" do
    it "runs the vips command with Paperclip.run" do
      Paperclip.options[:log_command] = false
      expect(Paperclip).to receive(:run).with("vips", "stuff", { :some => "args" })
      Paperclip::Processor.new("filename").vips("stuff", { :some => "args" })
    end
  end

  context "Calling #vipsheader" do
    it "runs the vipsheader command with Paperclip.run" do
      Paperclip.options[:log_command] = false
      expect(Paperclip).to receive(:run).with("vipsheader", "stuff", { :some => "args" })
      Paperclip::Processor.new("filename").vipsheader("stuff", { :some => "args" })
    end
  end
end
