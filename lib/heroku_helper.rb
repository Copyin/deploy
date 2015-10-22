class HerokuHelper
  # from https://github.com/heroku/heroku/issues/617#issuecomment-10723429
  def self.heroku_bin
    "GEM_HOME='' BUNDLE_GEMFILE='' GEM_PATH='' RUBYOPT='' /usr/local/heroku/bin/heroku"
  end
end