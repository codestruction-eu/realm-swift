#!/usr/bin/env ruby

require 'pathname'
require 'octokit'

VERSION = ARGV[1]
ACCESS_TOKEN = ENV['GITHUB_ACCESS_TOKEN']
raise 'GITHUB_ACCESS_TOKEN must be set to create GitHub releases' unless ACCESS_TOKEN

BUILD_SH = Pathname(__FILE__).+('../../build.sh').expand_path
RELEASE = "v#{VERSION}"

REPOSITORY = 'realm/realm-swift'

def release_notes(version)
  changelog = BUILD_SH.parent.+('CHANGELOG.md').readlines
  current_version_index = changelog.find_index { |line| line =~ (/^#{Regexp.escape version}/) }
  unless current_version_index
    raise "Update the changelog for the last version (#{version})"
  end
  current_version_index += 2
  previous_version_lines = changelog[(current_version_index+1)...-1]
  previous_version_index = current_version_index + (previous_version_lines.find_index { |line| line =~ /^\d+\.\d+\.\d+(-(alpha|beta|rc)(\.\d+)?)?\s+/ } || changelog.count)

  relevant = changelog[current_version_index..previous_version_index]

  relevant.join.strip
end

def create_draft_release
  name = 'Artifacts release'
  github = Octokit::Client.new
  github.access_token = ENV['GITHUB_ACCESS_TOKEN']

  puts 'Search for draft releases' # Previously created by a merge to master
  releases = github.releases(REPOSITORY)
  draft_releases = releases.select { |release| release[:name] == name && release[:draft] == true }

  draft_releases.each { |draf_release| 
    puts 'Deleting draft release' # Previously created by a merge to master
    response = github.delete_release(draf_release[:url])
  } 

  puts 'Creating GitHub draft release'
  response = github.create_release(REPOSITORY, RELEASE, name: name, body: "Artifacts release", draft: true)
  
  puts "Succesfully created draft release #{response[:url]}"
end

def create_release
  release_notes = release_notes(VERSION)
  github = Octokit::Client.new
  github.access_token = ENV['GITHUB_ACCESS_TOKEN']

  puts 'Creating GitHub release'
  prerelease = (VERSION =~ /alpha|beta|rc|preview/) ? true : false
  response = github.create_release(REPOSITORY, RELEASE, name: RELEASE, body: release_notes, prerelease: false)
  release_url = response[:url]

  Dir.glob 'release_pkg/*.zip' do |upload|
    puts "Uploading #{upload} to GitHub"
    github.upload_asset(release_url, upload, content_type: 'application/zip')
  end
end

def package_release_notes
  release_notes = release_notes(VERSION)
  FileUtils.mkdir_p("ExtractedChangelog")
  out_file = File.new("ExtractedChangelog/CHANGELOG.md", "w")
  out_file.puts(release_notes)
end

if ARGV[0] == 'create-draft-release'
  create_draft_release
elsif ARGV[0] == 'create-release'
  create_release
elsif ARGV[0] == 'package-release-notes'
  package_release_notes
end
