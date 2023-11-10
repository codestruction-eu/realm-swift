#!/usr/bin/env ruby

require 'octokit'
require 'getoptlong'
require 'uri'
require 'open-uri'
require 'fileutils'

require_relative "release-matrix"

include RELEASE

ACCESS_TOKEN = ENV['GITHUB_ACCESS_TOKEN']
raise 'GITHUB_ACCESS_TOKEN must be set to create GitHub releases' unless ACCESS_TOKEN

REPOSITORY = 'realm/realm-swift'

def update_package_asset(path, name, content_type)
    github = Octokit::Client.new
    github.access_token = ENV['GITHUB_ACCESS_TOKEN']
    
    response_get_releases = github.releases(REPOSITORY)
    draft_release = response_get_releases.select {|release| release[:name] == 'Artifacts release' && release[:draft] == true }
    puts "Draft release founded #{draft_release}"

    puts "Uploading asset #{name} for path: #{path}"
    release_url = draft_release[0][:url]
    puts "Release Url #{release_url}"
    response_upload_asset = github.upload_asset(release_url, path, { :name => "#{name}",  :content_type => content_type })
    puts response_upload_asset
end

def upload_product(name, path)
    puts "Uploading #{name} from #{path}"
    update_package_asset(path, name, 'application/zip')
end

def download_artifact(name, path)
    github = Octokit::Client.new
    github.access_token = ENV['GITHUB_ACCESS_TOKEN']
    
    response_get_release = github.releases(REPOSITORY)
    draft_release = response_get_release.select {|release| release[:name] == 'Artifacts release' && release[:draft] == true }
    puts "Draft release founded #{draft_release}"

    release_url = draft_release[0][:url]
    puts "Release Url #{release_url}"
    response_current_assets = github.release_assets(release_url)

    puts "Find asset #{name}"
    asset = response_current_assets.find{ |asset| asset[:name] == name }

    puts "Downloading asset #{asset[:url]}"
    download(asset[:url], path)
end

def download(url, path)
    open(path, 'wb') do |file|
        uri = URI.parse(url)
        io = uri.open("Authorization" => "Bearer #{ENV['GITHUB_ACCESS_TOKEN']}", 
            "Accept" => "application/octet-stream",
            )
        puts "Writing from temp #{io.path} to #{path}"
        case io
        when StringIO then
            File.open(path, 'w') { |f| f.write(io.read) }
        when Tempfile then 
            io.close; FileUtils.mv(io.path, path)
        end
    end
end

opts = GetoptLong.new(
    [ '--help', '-h', GetoptLong::NO_ARGUMENT ],
    [ '--path', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--upload-product', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--download-asset', GetoptLong::REQUIRED_ARGUMENT ]
)

option = ''
name = ''
path = ''

opts.each do |opt, arg|
    if opt != '--path'
        option = opt
    end
    case opt
        when '--help'
            puts <<-EOF
hello [OPTION] ...

-h, --help:
    show help

--upload-product
    Upload docs to the draft release

            EOF
            exit
        when '--path'
            if arg == ''
                raise "Path is required to execute this"
            else
                path = arg
            end
        when '--upload-product', '--download-asset'
            if arg == ''
                raise "Name is required to execute this"
            else
                name = arg
            end
    end
end

if option == '--upload-product'
    if name == '' || path == ''
        raise 'Missing product name or path.'
    else
        upload_product(name, path)
    end
elsif option == '--download-asset'
    if name == '' || path == ''
        raise 'Missing product name or path.'
    else
        download_artifact(name, path)
    end
end
