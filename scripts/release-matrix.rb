#!/usr/bin/env ruby

module RELEASE
    DOCS_XCODE_VERSION = '14.3.1'
    XCODE_VERSIONS = ['14.1', '14.2', '14.3.1', '15.0.1', '15.1']
    PLATFORMS_NAMES = ['osx': 'macOS', 'ios': 'iOS', 'watchos': 'watchOS', 'tvos': 'tvOS', 'catalyst': 'Catalyst', 'visionos': 'visionOS']
    
    all = ->(v) { true }
    latest_only = ->(v) { v == XCODE_VERSIONS.last }
    doc_version = ->(v) { v == DOCS_XCODE_VERSION }

    PLATFORMS = {
      'osx' => all,
      'ios' => all,
      'watchos' => all,
      'tvos' => all,
      'catalyst' => all,
      'visionos' => latest_only,
    }

    RELEASE_XCODE_CLOUD_TARGETS = {
      'package-docs' => doc_version,
      'package' => all,
      'test-package-examples' => latest_only,
      'test-ios-static' => latest_only,
      'test-osx' => latest_only,
      'test-installation-osx-xcframework-dynamic' => all,
      'test-installation-ios-xcframework-dynamic' => doc_version,
      'test-installation-watchos-xcframework-dynamic' => doc_version,
      'test-installation-tvos-xcframework-dynamic' => doc_version,
      'test-installation-catalyst-xcframework-dynamic' => doc_version,
      'test-installation-ios-xcframework-static' => doc_version,
    }
end

def get_doc_version
    puts "#{RELEASE::DOCS_XCODE_VERSION}"
end

def plaforms_for_version(version)
    platforms_version = []
    RELEASE::PLATFORMS.each { |platform, filter|
        if filter.call(version)
            platforms_version.append(platform)
        end
    }
    puts "#{platforms_version.join(",")}"
end

def get_xcode_versions
    puts "#{RELEASE::XCODE_VERSIONS.join(",")}"
end

if ARGV[0] == 'docs_version'
    get_doc_version
elsif ARGV[0] == 'plaforms_for_version'
    version = ARGV[1]
    plaforms_for_version(version)
elsif ARGV[0] == 'xcode_versions'
    get_xcode_versions
end
