Gem::Specification.new do |s|
  s.name         = "deploy"
  s.version      = "0.1"
  s.license      = "MIT"
  s.authors      = ["Ed Saunders"]
  s.email        = ["ed@twistilled.com"]
  s.homepage     = "http://twistilled.com"
  s.summary      = "Deployment scripts for twistilled apps onto Heroku"
  s.description  = "Manages tagging and pushing to Heroku, along with running migrations"

  s.add_dependency "rails", "~> 4.1"

  s.add_development_dependency "rspec", "~> 3.3"
  s.add_development_dependency "pry", "~> 0.10.1"

  s.files         = `git ls-files`.split($/)
  s.test_files    = s.files.grep(%r{^spec/})
  s.require_paths = ["lib"]
  s.executables   = ["deploy"]
end
