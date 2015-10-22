require "pathname"
require "shellwords"
require_relative "shell_cmd"
require_relative "heroku_helper"

class DbHelper
  PRODUCTION_DB_DUMP_FILE = Pathname.new(File.expand_path File.dirname(__FILE__)).join "..", "ptw-production-db.dump"

  def initialize environment
    @environment = environment
  end

  def import_production_db_dump
    if File.exists? PRODUCTION_DB_DUMP_FILE
      puts "(existing '#{PRODUCTION_DB_DUMP_FILE}', file, so we don't download the latest Heroku db backup. If you want to have it downloaded, remove this file and rerun your command)"
    else
      puts "Downloading latest Heroku db backup..."
      # from https://github.com/heroku/heroku/issues/617#issuecomment-10723429
      heroku_pg_backup_url_cmd = "#{HerokuHelper.heroku_bin} pgbackups:url -a brojure"
      ShellCmd.new("curl -o #{Shellwords.escape PRODUCTION_DB_DUMP_FILE.to_s} `#{heroku_pg_backup_url_cmd}`").run with_system: true
    end
    #puts "Importing the production db dump in the '#{@environment}' db..."
    #ShellCmd.new("pg_restore --verbose --no-acl --no-owner -h localhost -d brojure_#{@environment} #{Shellwords.escape PRODUCTION_DB_DUMP_FILE.to_s}").run
  end

  def self.restart_postgresl
    # =============================================
    # XL - 2013.11.20
    # I haven't this script, comment it now
    # TODO XL need to be updated to another script.
    #ShellCmd.new("pg_ctl -D /usr/local/var/postgres stop -s -m fast").run ignore_failure: true
    #ShellCmd.new("pg_ctl -D /usr/local/var/postgres -l /usr/local/var/postgres/server.log start").run
  end

end