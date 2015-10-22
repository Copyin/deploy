# Deploy

This manages the deployments for Twistilled repos to Heroku. It's been extracted from the original Twistilled repo and converted to a gem to make it reusable across apps.

## Usage

Usage is vey coarse at the moment:

1. Create a branch off `master` named the same as your app
1. Adjust the various constants at the top (e.g. repo location) to fit your app
1. Modify as necessary on your branch
1. Add a line to your gemfile as follows:
  * See the `lightup` branch for some examples of this

```ruby
  gem "deploy", git: "https://github.com:Twistilled/deploy.git", ref: "<your_app_name>"
```

Then you can kick off a deploy but just typing:

    $ deploy

## TODO

* Write some specs so we can refactor safely
* Add a "dry-run" mode for testing
* Refactor so that we don't need specific branches, instead read configs from a file checked into the application's git repo
  * In particular, make handle the staging/no-staging difference between twistilled and lightup
