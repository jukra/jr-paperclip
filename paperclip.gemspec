$LOAD_PATH.push File.expand_path("lib", __dir__)
require "paperclip/version"

Gem::Specification.new do |s|
  s.name              = "jr-paperclip"
  s.version           = Paperclip::VERSION
  s.platform          = Gem::Platform::RUBY
  s.author            = "Jukka Rautanen"
  s.email             = ["jukka.rautanen@gmail.com"]
  s.homepage          = "https://github.com/jukra/jr-paperclip"
  s.summary           = "File attachments as attributes for ActiveRecord"
  s.description       = "Easy upload management for ActiveRecord"
  s.license           = "MIT"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map { |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.post_install_message = File.read("UPGRADING") if File.exist?("UPGRADING")

  s.requirements << "ImageMagick"
  s.required_ruby_version = ">= 3.2.0"

  s.add_dependency("activemodel", ">= 7.0.0")
  s.add_dependency("activesupport", ">= 7.0.0")
  s.add_dependency("marcel", ">= 1.0.1")
  s.add_dependency("mime-types")
  s.add_dependency("terrapin", ">= 0.6.0", "< 2.0")

  s.add_development_dependency("activerecord", ">= 7.0.0")
  s.add_development_dependency("appraisal")
  s.add_development_dependency("aruba", "~> 2.0")
  s.add_development_dependency("aws-sdk-s3")
  s.add_development_dependency("bundler")
  s.add_development_dependency("capybara")
  s.add_development_dependency("cucumber", "~> 9.0")
  s.add_development_dependency("cucumber-rails", "~> 3.0")
  s.add_development_dependency("fog-aws")
  s.add_development_dependency("fog-local")
  s.add_development_dependency("generator_spec")
  s.add_development_dependency("launchy")
  s.add_development_dependency("nokogiri")
  s.add_development_dependency("ostruct")
  s.add_development_dependency("railties")
  s.add_development_dependency("rake")
  s.add_development_dependency("rspec", "~> 3.0")
  s.add_development_dependency("shoulda")
  s.add_development_dependency("timecop")
  s.add_development_dependency("webmock")
end
