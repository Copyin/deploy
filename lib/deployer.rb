# ------------------
# From Gems
require "colored"
require "highline/import"
require 'sys/proctable'
require "pony"
# ------------------
# From Ruby Std Lib
require "pathname"
require "shellwords"
# ------------------
require_relative "./db_helper"
require_relative "./shell_cmd"
require_relative "./heroku_helper"

class Deployer

  PRODUCTION_ALIAS = 'production'
  PRODUCTION_BRANCH = 'master'
  DEVELOPMENT_BRANCH = 'staging'
  GIT_ALIAS = 'origin'
  GIT_URL = 'https://github.com/Twistilled/lightup'
  APP_NAME = 'lightupbiz'

  DEPLOYMENT_MAIL = 'releases@twistilled.copyin.com'
  DEPLOYMENT_SENDER = {
      :address              => 'smtp.gmail.com',
      :port                 => '587',
      :enable_starttls_auto =>  true,
      :user_name            => 'twistilledbot@gmail.com',
      :password             => 'Bwu2BTEWBkqZL8',
      :authentication       => :plain,
      :domain               => 'gmail.com'
  }

  def deploy
    @start_time = Time.now
    @backup_production_db, @test_migrations, @run_tests = 'y'
    @merge_development_in_master, @bypass_current_branch_and_head_check = "n"

    run_step "Performing initial quick checks..." do
      if current_branch == PRODUCTION_BRANCH &&
          @merge_development_in_master == "y" &&
          yes_or_no?("You've started the script from the #{PRODUCTION_BRANCH} branch. Do you want to just push a hotfix? (y/n)") == "y"

        @current_branch = PRODUCTION_BRANCH
      elsif @merge_development_in_master == "n"
        abort_and_warn_user "Could not checkout the #{PRODUCTION_BRANCH} branch" unless system("git checkout #{PRODUCTION_BRANCH}")
        @current_branch = PRODUCTION_BRANCH
      else
        abort_and_warn_user "Could not checkout the #{DEVELOPMENT_BRANCH} branch" unless system("git checkout #{DEVELOPMENT_BRANCH}")
        @current_branch = DEVELOPMENT_BRANCH
      end
      @current_head_commit = `git rev-parse HEAD`

      # uncomment this line to use the deployer with uncommited change
      # @bypass_current_branch_and_head_check = "y"
      #
      # AND comment this line to use the deployer with uncommited change
      abort_and_warn_user "There are uncommitted changes, please commit or reset them" unless `git status -s`.empty?

      # here we don't need to check if there are uncommitted changes in master,
      # because if there were we would not have been able to checkout
      # development, or they would appear in development too
      abort_and_warn_user "Please set an environment variable that contains your editor executable ('vim', 'mate'...). \n. You can do this by opening adding the line 'EDITOR=\"your-editor\"' in ~/.bash_profile" if `echo $EDITOR`.chomp.empty?
    end

    run_step "Just a few questions before we get going..." do

      @deployer_name = get_deployer_name

      @merge_development_in_master = if @current_branch == PRODUCTION_BRANCH
                                       "n"
                                     else
                                        yes_or_no?("\nMerge the latest commits from #{DEVELOPMENT_BRANCH} into #{PRODUCTION_BRANCH}? (y/n) \n(answer 'n' if you're just pushing a hotfix to the #{PRODUCTION_BRANCH} branch)")
                                     end

      @run_tests = yes_or_no?("\nDo you want to run the tests? (y/n) \n(answer 'n' only if you are really sure it is not necessary)")

      @backup_production_db = ask_if_backup_production_db

      @previous_tag_name, @tag_name, @tag_message_lines = get_info_for_release_tag
    end

    run_step "Fetching remote branches..." do
      run_cmd "git fetch #{GIT_ALIAS}"
      run_cmd "git fetch #{PRODUCTION_ALIAS}"
    end

    run_step "Getting info for the release tag..." do
    end

    if @merge_development_in_master == "y"
      run_step "Checking that your local #{DEVELOPMENT_BRANCH} branch is up to date with the #{DEVELOPMENT_BRANCH} branch on Github..." do
        check(
          cmd:       "git shortlog #{DEVELOPMENT_BRANCH}...#{GIT_ALIAS}/#{DEVELOPMENT_BRANCH}",
          condition: ->(cmd_result) { cmd_result.empty? },
          message:   "Please make sure that your #{DEVELOPMENT_BRANCH} branch and Github are in sync and that neither is ahead of the other. \nThey need to be up-to-date because we will automatically merge any hotfixes you do back into #{DEVELOPMENT_BRANCH} so that everyone can benefit from them."
        )
      end
    end

    run_step "Checking that your local #{PRODUCTION_BRANCH} branch includes all commits from the GitHub #{PRODUCTION_BRANCH} branch..." do
      check(
        cmd:       "git shortlog #{PRODUCTION_BRANCH}..#{GIT_ALIAS}/#{PRODUCTION_BRANCH}",
        condition: ->(cmd_result) { cmd_result.empty? },
        message:   "Some commits in the #{PRODUCTION_BRANCH} branch on GitHub are not in your local #{PRODUCTION_BRANCH} branch. Please update your #{PRODUCTION_BRANCH} branch to match the head of Github."
      )
    end

    run_step "Checking that the local #{PRODUCTION_BRANCH} branch includes all commits from the #{PRODUCTION_BRANCH} branch..." do
      check(
        cmd:       "git shortlog #{PRODUCTION_BRANCH}..#{PRODUCTION_ALIAS}/#{PRODUCTION_BRANCH}",
        condition: ->(cmd_result) { cmd_result.empty? },
        message:   "Some commits in the #{PRODUCTION_BRANCH} branch are not in your local #{PRODUCTION_BRANCH} branch. Please update your #{PRODUCTION_BRANCH} branch to match the head of production."
      )
    end

    run_step "Moving to the #{PRODUCTION_BRANCH} branch..." do
      run_cmd "git checkout #{PRODUCTION_BRANCH}"
      @current_branch      = "#{PRODUCTION_BRANCH}"
      @current_head_commit = `git rev-parse HEAD`
    end

    if @merge_development_in_master == 'y'
      run_step "Merge #{DEVELOPMENT_BRANCH} into #{PRODUCTION_BRANCH}..." do
        run_cmd "git merge #{DEVELOPMENT_BRANCH}"
        @current_head_commit = `git rev-parse HEAD`
      end
    end

    if @run_tests == "y"
      run_step "Running tests..." do
        deployer_success_test_sha_file = ".deployer_sha_of_latest_successful_tests"
        if File.exists?(deployer_success_test_sha_file) && @current_head_commit == IO.read(deployer_success_test_sha_file)
          puts "Bypassed because tests have already successfully passed with the current code"
        else
          # kill guard to avoid concurrent access to the test db
          kill_process "bin/guard"
          # kill spork because it might have be started with a version of the code
          # that is not the version of the code we are going to deploy
          kill_process "spork"
          # Why restarting postgres...?
          # DbHelper.restart_postgresl
          run_cmd "bundle exec rake db:test:prepare"

          run_cmd "bundle exec rspec spec", with_system: true

          File.open(deployer_success_test_sha_file, 'w') { |f| f.write @current_head_commit }
        end
      end
    end

    backup_production_db if @backup_production_db == "y"
    test_migrations if @test_migrations == 'y'

    run_step "Pushing to the Heroku production application... (Sainte Marie, Mère de Dieu, priez pour nous)" do
      run_cmd "git push #{PRODUCTION_ALIAS} #{PRODUCTION_BRANCH}", with_system: true
    end

    run_step "Record deployment in New Relic" do
      # XL 2013.11.20
      # TODO how to enable newrelic?
      #run_cmd "newrelic deployments -u '#{@deployer_name}' -r #{@tag_name}"
    end

    changed_files = `git log --name-only #{@previous_tag_name}..HEAD`
    if changed_files.include?("app/helpers") || changed_files.include?("app/decorators")
      run_step "Flushing the cache on the Heroku production application..." do
        run_cmd "#{HerokuHelper.heroku_bin} run rails runner 'Rails.cache.clear' -a #{APP_NAME}"
      end
    end

    run_step "Running migrations on the Heroku production application..." do
      run_cmd "#{HerokuHelper.heroku_bin} run rake db:migrate -a #{APP_NAME}", with_system: true
    end

    run_step "Restarting the Heroku production application..." do
      run_cmd "#{HerokuHelper.heroku_bin} restart -a #{APP_NAME}"
    end

    run_step "Creating the new release tag..." do
      run_cmd "git tag -a #{@tag_name} -m $'#{@tag_message}'"
    end

    run_step "Pushing #{PRODUCTION_BRANCH} back to GitHub..." do
      run_cmd "git push #{GIT_ALIAS} #{PRODUCTION_BRANCH}"
      run_cmd "git push --tags #{GIT_ALIAS}"
    end

    if @merge_development_in_master == "y"
      run_step "Merging #{PRODUCTION_BRANCH} into #{DEVELOPMENT_BRANCH} and pushing #{DEVELOPMENT_BRANCH} back to GitHub..." do
        run_cmd "git checkout #{DEVELOPMENT_BRANCH}"
        @current_branch      = "#{DEVELOPMENT_BRANCH}"
        @current_head_commit = `git rev-parse HEAD`
        run_cmd "git pull --rebase #{GIT_ALIAS} #{DEVELOPMENT_BRANCH} "
        @current_head_commit = `git rev-parse HEAD`
        run_cmd "git merge #{PRODUCTION_BRANCH}"
        @current_head_commit = `git rev-parse HEAD`
        run_cmd "git push #{GIT_ALIAS} #{DEVELOPMENT_BRANCH}"
      end
    end

    puts
    tell_user "Deploy successfully finished!"
    puts "Hurray!!! It's over :) Please check everything works fine on #{APP_NAME}.herokuapp.com".green
    puts

    puts "This deploy took #{Time.now - @start_time} seconds to run."

    run_step "Now sending the release info email to #{DEPLOYMENT_MAIL}..." do
      email_html_body = @tag_message_lines.join '<br />'
      email_html_body += "<hr /><a href='#{GIT_URL}/compare/#{@previous_tag_name}...#{@tag_name}'>See the complete list of commits</a>"
      send_release_infos_to_release_mailing_list @deployer_name, @tag_name, email_html_body
    end
  end

  def only_test_migrations
    @bypass_current_branch_and_head_check = "y"
    DbHelper.restart_postgresl
    backup_production_db if ask_if_backup_production_db == "y"
    test_migrations
  end

  private

  def abort_and_warn_user message
    tell_user message, "deploy script failed"
    abort
  end

  def ask_if_backup_production_db
    production_db_dump_file_is_fresh = File.exists?(DbHelper::PRODUCTION_DB_DUMP_FILE) && (Time.now - File.mtime(DbHelper::PRODUCTION_DB_DUMP_FILE) < 60 * 60)
    if production_db_dump_file_is_fresh
      yes_or_no?("You have a local dump file of the Heroku production db that has been pulled less than 1 hour ago. Do you want to create a new db backup and pull locally the production db again or not? (y/n) (answer 'n' only if you have ran this script very recently so it has already done a backup fresh enough)")
    else
      "y"
    end
  end

  def backup_production_db
    # run_step "Creating a manual backup of the Heroku production db..." do
    #   run_cmd "#{HerokuHelper.heroku_bin} pgbackups:capture -a #{APP_NAME} --expire", with_system: true, in_background: (@test_migrations != 'y')
    # end
  end

  def check args
    cmd       = args.fetch :cmd
    condition = args.fetch :condition
    message   = args.fetch :message

    cmd_result = run_cmd cmd
    unless condition.call(cmd_result)
      tell_user message, "script error"
      if yes_or_no?("Do you want this check to be rerun (if you can fix the issue before)? If no, the script will be aborted (y/n)") == "y"
        check args
      else
        abort "deploy script aborted".red
      end
    end
  end

  def current_branch
    `git branch`[/\* (.+)/]
    $1
  end

  def get_deployer_name
    deployer_name      = ""
    deployer_name_file = ".deployer_name"

    if File.exists? deployer_name_file
      deployer_name = IO.read deployer_name_file
    else
      deployer_name = ask("What's your name bro?") { |q| q.validate = /\S+/ }
      File.open(deployer_name_file, 'w') { |f| f.write deployer_name }
    end

    deployer_name
  end

  def get_info_for_release_tag
    run_cmd "git fetch --tags #{GIT_ALIAS}"

    tag_message_file = Shellwords.escape("/tmp/#{APP_NAME}-deploy-tag-message.txt")

    File.open(tag_message_file, "w") do |file|
      file.puts deploy_template
      relevant_messages_from_git_history.each {|message| file.puts message}
    end

    tell_user "check your editor to create the tag release message", "check your editor"
    system "$EDITOR #{tag_message_file}"

    previous_tag_name  = `git describe --abbrev=0`.chomp

    previous_tag_date, previous_tag_version, previous_tag_hotfix = previous_tag_name.split(".")

    new_tag_date = Date.today.to_datetime.strftime("%Y%m%d")

    if new_tag_date != previous_tag_date
      # New day, so everything's new!
      new_tag_version = 1
      new_tag_hotfix = nil
    else
      if yes_or_no?("Is this a hotfix? (y/n)") == "n"
        new_tag_version = previous_tag_version.to_i + 1
        new_tag_hotfix = nil
      else
        new_tag_version = previous_tag_version
        new_tag_hotfix = previous_tag_hotfix.nil? ? 1 : previous_tag_hotfix.to_i + 1
      end
    end

    tag_name = [new_tag_date, new_tag_version, new_tag_hotfix].compact.join(".")

    run_cmd "cp #{tag_message_file} /tmp/last-deploy-tag-message.txt"

    tag_message_lines = File.readlines(tag_message_file).select { |line| line !~ /^#[^#]/ }.map(&:chomp)
    tag_message       = tag_message_lines.join '\n'
    tag_message.gsub! "'", "\\\\'"

    [previous_tag_name, tag_name, tag_message_lines]
  end

  def relevant_messages_from_git_history
    all_merge_comments = run_cmd "git log --merges --pretty=format:'%B' $(git describe --abbrev=0 --tags)..HEAD"
    all_merge_comments.split("\n").reject do |line|
      line == "" || line =~ /^Merge /
    end
  end

  def kill_process string
    Sys::ProcTable.ps.each do |ps|
      Process.kill('KILL', ps.pid) if ps.cmdline.include?(string)
    end
  end

  def make_sure_is_on_current_branch_without_uncommitted_changes_and_with_correct_head
    return if @bypass_current_branch_and_head_check == "y"

    while !(`git branch` =~ /\* #{@current_branch}/) do
      tell_user "The current branch in your repository is no more the #{@current_branch} branch. Please checkout again the #{@current_branch} branch.", "script error"
      abort if yes_or_no?("Continue with deploy script (y) or abort (n)?") == "n"
    end
    while !`git status -s`.empty? do
      tell_user "There are uncommitted changes in your #{@current_branch} branch. Please commit, stash or reset them.", "script error"
      abort if yes_or_no?("Continue with deploy script (y) or abort (n)?") == "n"
    end
    if `git rev-parse HEAD` != @current_head_commit
      tell_user "The HEAD has changed since the start of the script, it is no more #{@current_head_commit}. If that is not expected revert to the previous HEAD before going on. You can also go on with the script, the new current HEAD will be considered the correct one.", "script warning"
      abort if yes_or_no?("Continue with deploy script (y) or abort (n)?") == "n"
      @current_head_commit = `git rev-parse HEAD`
    end
  end

  def run_cmd cmd_string, options={}
    make_sure_is_on_current_branch_without_uncommitted_changes_and_with_correct_head
    puts cmd_string.cyan
    ShellCmd.new(cmd_string).run options
  rescue ShellCmd::Failure
    if yes_or_no?("Do you want the commmand to be rerun (if you can fix the issue before)? If no, the script will be aborted (y/n)") == "y"
      run_cmd cmd_string, options
    else
      abort "deploy script aborted".red
    end
  end

  def run_step description, &block
    puts description.blue
    yield
    puts
  end

  def send_release_infos_to_release_mailing_list deployer_name, tag_name, email_html_body
    Pony.mail({
      to:        DEPLOYMENT_MAIL,
      from:      DEPLOYMENT_SENDER[:user_name],
      subject:   "#{tag_name} [cooked by #{deployer_name}]",
      html_body: email_html_body,
      via:       :smtp,
      via_options: DEPLOYMENT_SENDER
    })
  end

  def tell_user message, notification_message=message
    puts message.magenta
    # puts "Notification through growlnotify failed".red unless system "growlnotify -m '#{notification_message}'"
    # removed growl because it's not on my machine any more :)
    system "say '#{notification_message}' &" if `which say` && `which say` != ""
  end

  def test_migrations
    run_step "Downloading last production backup and importing it in your local test database..." do
      run_cmd "bundle exec rake RAILS_ENV=test db:import_production_db_backup"
    end

    run_step "Running migrations on this imported data..." do
      run_cmd "bundle exec rake RAILS_ENV=test db:migrate"
    end
  end

  def yes_or_no? question
    ask(question.yellow) { |q| q.validate = /^y|n$/ }
  end

  def deploy_template
    <<-TEMPLATE
# The commits in this release are all shown below. Edit them to produce a
# helpful description which will be emailed to the releases list....
#
# Format in markdown. For example (bear in mind lines starting with a single
# "#" will be removed before emailing, so prefer bold for section headings):
#
# **New Features**
#
# - Made this **awesome** new feature (92398819)
#
# **Bug fixes**
#
# - Fixed that well [annoying bug](http://bugsnag.com/some/bug) (93321469)
#

# Delete where not applicable

**New Features**



**UX Design**



**Bug fixes**



**Architecture (e.g. refactoring)**



# Leave a blank line at the end to ensure formatting correct with the link to
# the diffs

    TEMPLATE
  end
end
