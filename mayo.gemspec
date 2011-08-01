# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "mayo/version"

Gem::Specification.new do |s|
  s.name        = "mayo"
  s.version     = Mayo::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Sujimichi"]
  s.email       = ["sujimichi@gmail.com"]
  s.homepage    = ""
  s.summary     = %q{A noobish simplistic attempt at distributing cucumber features}
  s.description = s.summary

  s.rubyforge_project = "mao"

  s.add_development_dependency('rspec')
  s.add_development_dependency('ZenTest')
  s.add_dependency('dalli')
  s.add_dependency('json')


  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

end
