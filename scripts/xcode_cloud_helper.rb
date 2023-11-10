#!/usr/bin/env ruby
require 'net/http'
require 'net/https'
require 'uri'
require 'json'
require "base64"
require "jwt"
require 'getoptlong'
require_relative "pr-ci-matrix"
require_relative "release-matrix"

include WORKFLOWS
include RELEASE

JWT_BEARER = ''
TEAM_ID = ''
$product_id = ''
$repository_id = ''
$xcode_list = ''
$mac_dict = Hash.new
$workflows_list = ''

def usage()
    puts <<~END
    Usage: ruby #{__FILE__} --list-workflows --token [token]
    Usage: ruby #{__FILE__} --list-products --token [token]
    Usage: ruby #{__FILE__} --list-repositories --token [token]
    Usage: ruby #{__FILE__} --list-mac-versions --token [token]
    Usage: ruby #{__FILE__} --list-xcode-versions --token [token]
    Usage: ruby #{__FILE__} --info-workflow [workflow_id] --token [token]
    Usage: ruby #{__FILE__} --create-workflow [name] --xcode-version [xcode_version] --token [token]
    Usage: ruby #{__FILE__} --delete-workflow [workflow_id] --token [token]
    Usage: ruby #{__FILE__} --build-workflow [workflow_id] --token [token]
    Usage: ruby #{__FILE__} --create-new-workflows --token [token] --team-id [team_id]
    Usage: ruby #{__FILE__} --create-relase-new-workflow --token [token] --team-id [team_id]
    Usage: ruby #{__FILE__} --clear-unused-workflows --token [token]
    Usage: ruby #{__FILE__} --get-token --issuer-id [issuer_id] --key-id [key_id] --pk_path [pk_path]
    Usage: ruby #{__FILE__} --run-release-workflow [name] --token [token]

    environment variables:
    END
    exit 1
end

APP_STORE_URL="https://api.appstoreconnect.apple.com/v1"

def sh(*args)
    puts "executing: #{args.join(' ')}" if false
    system(*args, false ? {} : {:out => '/dev/null'}) || exit(1)
end

def get_jwt_bearer(issuer_id, key_id, pk_path)
    private_key = OpenSSL::PKey.read(File.read(pk_path))
    info = {
        iss: issuer_id,
        exp: Time.now.to_i + 10 * 60,
        aud: "appstoreconnect-v1"
    }
    header_fields = { kid: key_id }
    token = JWT.encode(info, private_key, "ES256", header_fields)
    puts "Token -> #{token}"
end

def get_workflows
    product_id = get_realm_product_id
    response = get("/ciProducts/#{product_id}/workflows?limit=200")
    result = JSON.parse(response.body)
    list_workflows = []
    result.collect do |doc|
        doc[1].each { |workflow|
            if workflow.class == Hash
                list_workflows.append(workflow)
            end
        }
    end
    return list_workflows
end

def get_products
    response = get("/ciProducts")
    result = JSON.parse(response.body)
    list_products = []
    result.collect do |doc|
        doc[1].each { |prod|
            if prod.class == Hash
                list_products.append({ "product" => prod["attributes"]["name"], "id" => prod["id"], "type" => prod["attributes"]["productType"] })
            end
        }
    end
    return list_products
end

def get_build_actions(build_run)
    response = get("/ciBuildRuns/#{build_run}/actions")
    result = JSON.parse(response.body)
    list_actions = []
    result.collect do |doc|
        doc[1].each { |action|
            if action.class == Hash
                list_actions.append({ "id" => action["id"] })
            end
        }
    end
    return list_actions
end

def get_artifacts(build_action)
    response = get("/ciBuildActions/#{build_action}/artifacts")
    result = JSON.parse(response.body)
    list_artifacts = []
    result.collect do |doc|
        doc[1].each { |artifact|
            if artifact.class == Hash
                list_artifacts.append({ "id" => artifact["id"] })
            end
        }
    end
    return list_artifacts
end

def get_repositories
    response = get("/scmRepositories")
    result = JSON.parse(response.body)
    list_repositories = []
    result.collect do |doc|
        doc[1].each { |repo|
            if repo.class == Hash
                list_repositories.append({ "name" => repo["attributes"]["repositoryName"], "id" => repo["id"], "url" => repo["attributes"]["httpCloneUrl"] })
            end
        }
    end
    return list_repositories
end

def get_macos_versions
    response = get("/ciMacOsVersions")
    result = JSON.parse(response.body)
    list_macosversion = []
    result.collect do |doc|
        doc[1].each { |macos|
            if macos.class == Hash
                list_macosversion.append({ "name" => macos["attributes"]["name"], "id" => macos["id"], "version" => macos["attributes"]["version"] })
            end
        }
    end
    return list_macosversion
end

def get_xcode_versions
    response = get("/ciXcodeVersions")
    result = JSON.parse(response.body)
    list_xcodeversion = []
    result.collect do |doc|
        doc[1].each { |xcode|
            if xcode.class == Hash
                list_xcodeversion.append({ "name" =>  xcode["attributes"]["name"], "id" => xcode["id"], "version" => xcode["attributes"]["version"] })
            end
        }
    end
    return list_xcodeversion
end

def print_workflow_info(id)
    workflow_info = get_workflow_info(id)
    puts "Workflow Info:"
    puts workflow_info
end

def get_workflow_info(id)
    response = get("/ciWorkflows/#{id}")
    return response.body
end

def get_build_action_info(id)
    response = get("/ciBuildActions/#{id}")
    return response.body
end

def get_artifact_info(id)
    response = get("/ciArtifacts/#{id}")
    return response.body
end

def get(path)
    url = "#{APP_STORE_URL}#{path}"
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(uri.request_uri)
    request["Authorization"] = "Bearer #{JWT_BEARER}"
    request["Accept"] = "application/json"
    response = http.request(request)

    if response.code == "200"
        return response
    else
        raise "Error: #{response.code} #{response.body}"
    end
end

def create_workflow(name, xcode_version, prefix = "")
    url = "#{APP_STORE_URL}/ciWorkflows"
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{JWT_BEARER}"
    request["Content-type"] = "application/json"
    body = create_workflow_request(name, xcode_version, prefix)
    request.body = body.to_json
    response = http.request(request)
    if response.code == "201"
        result = JSON.parse(response.body)
        id = result["data"]["id"]
        puts "Worfklow created id: #{id} target: #{prefix}#{name} xcode version: #{xcode_version}"
        product_id = get_realm_product_id
        puts "https://appstoreconnect.apple.com/teams/#{TEAM_ID}/frameworks/#{product_id}/workflows/#{id}"
        return id
    else
        raise "Error: #{response.code} #{response.body}"
    end
end

def create_workflow_request(name, xcode_version, prefix = "")
    build_action = get_action_for_target(name)
    pull_request_start_condition =
    {
        "source" => { "isAllMatch" => true, "patterns" => [] },
        "destination" => { "isAllMatch" => true, "patterns" => [] },
        "autoCancel" => true
    }
    attributes =
    {
        "name" => "#{prefix}#{name}_#{xcode_version}",
        "description" => 'Create by Github Action Update XCode Cloud Workflows',
        "isLockedForEditing" => false,
        "containerFilePath" => "Realm.xcodeproj",
        "isEnabled" => false,
        "clean" => false,
        "pullRequestStartCondition" => pull_request_start_condition,
        "actions" => build_action
    }

    xcode_version_id = get_xcode_id(xcode_version)
    mac_os_id = get_macos_latest_release(xcode_version_id)
    relationships =
    {
        "xcodeVersion" => { "data" => { "type" => "ciXcodeVersions", "id" => xcode_version_id }},
        "macOsVersion" => { "data" => { "type" => "ciMacOsVersions", "id" => mac_os_id }},
        "product" => { "data" => { "type" => "ciProducts", "id" => get_realm_product_id }},
        "repository" => { "data" => { "type" => "scmRepositories", "id" => get_realm_repository_id }}
    }
    data =
    {
        "type" => "ciWorkflows",
        "attributes" => attributes,
        "relationships" => relationships
    }
    body = { "data" => data }
    return body
end

def update_workflow(id, data)
    url = "#{APP_STORE_URL}/ciWorkflows/#{id}"
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Patch.new(uri)
    request["Authorization"] = "Bearer #{JWT_BEARER}"
    request["Content-type"] = "application/json"
    body = { "data" => data }
    request.body = body.to_json
    response = http.request(request)
    if response.code == "200"
        result = JSON.parse(response.body)
        id = result["data"]["id"]
        puts "Worfklow updated #{id}"
        return id
    else
        raise "Error: #{response.code} #{response.body}"
    end
end

def delete_workflow(id)
    url = "#{APP_STORE_URL}/ciWorkflows/#{id}"
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Delete.new(uri)
    request["Authorization"] = "Bearer #{JWT_BEARER}"
    request["Content-type"] = "application/json"
    response = http.request(request)
    if response.code == "204"
        puts "Workflow deleted #{id}"
    else
        raise "Error: #{response.code} #{response.body}"
    end
end

def start_build(id)
    url = "#{APP_STORE_URL}/ciBuildRuns"
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{JWT_BEARER}"
    request["Content-type"] = "application/json"
    data =
    {
        "type" => "ciBuildRuns",
        "attributes" => { "clean" => true },
        "relationships" => { "workflow" => { "data" => { "type" => "ciWorkflows", "id" => id }}}
    }
    body = { "data" => data }
    request.body = body.to_json
    response = http.request(request)
    if response.code == "201"
        result = JSON.parse(response.body)
        build_id = result["data"]["id"]
        puts "Workflow build started with id: #{id}:"
        puts "Running build https://appstoreconnect.apple.com/teams/#{TEAM_ID}/frameworks/#{get_realm_product_id}/builds/#{build_id}/"
        puts response.body
        return build_id
    else
        raise "Error: #{response.code} #{response.body}"
    end
end

def get_macos_versions_for_xcode_version(version)
    url = "#{APP_STORE_URL}/ciXcodeVersions/#{version}/macOsVersions"
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(uri.request_uri)
    request["Authorization"] = "Bearer #{JWT_BEARER}"
    request["Accept"] = "application/json"
    response = http.request(request)

    if response.code == "200"
        result = JSON.parse(response.body)

        list_macosversion = {}
        result.collect do |doc|
            doc[1].each { |macos|
                if macos.class == Hash
                    name = macos["attributes"]["name"]
                    id = macos["id"]
                    list_macosversion.store(name, id)
                end
            }
        end
        return list_macosversion
    else
        raise "Error: #{response.code} #{response.body}"
    end
end

def create_new_workflows
    if !ENV.include?('CI')
        print "Are you sure you want to create this workflows?, this will create declared local workflows that may not currently working in other PRs [Y/N]\n"
        user_input = STDIN.gets.chomp.downcase
    else 
        user_input = 'y'
    end

    if user_input == "y"
        workflows_to_create = []
        current_workflows = get_workflows().map { |workflow| 
            name = workflow["attributes"]["name"].partition('_').first
            version = workflow["attributes"]["name"].partition('_').last
            { "target" => name, "version" => version }
        }
        WORKFLOWS::TARGETS.each { |name, filter|
            WORKFLOWS::XCODE_VERSIONS.each { |version|
                if filter.call(version)
                    workflow = { "target" => name, "version" => version }
                    unless current_workflows.include? workflow
                        workflows_to_create.append(workflow)
                    end
                end
            }
        }

        workflows_to_create.each { |workflow|
            name = workflow['target']
            version = workflow['version']
            puts "Creating new workflow for target: #{name} and version #{version}"
            workflow_id = create_workflow(name, version)
        }
    else
        puts "No"
    end
end

def create_new_release_workflows
    if !ENV.include?('CI')
        print 'Are you sure you want to create this workflows?, this will create declared local workflows that may not currently working in other PRs [Y/N]\n'
        user_input = STDIN.gets.chomp.downcase
    else 
        user_input = 'y'
    end

    if user_input == "y"
        current_workflows = get_workflows()
        .filter {  |workflow| 
            workflow["attributes"]["name"].split('_').first == 'release' 
        }
        .map { |workflow| 
            target = workflow["attributes"]["name"].split('_')
            name = target[1]
            version = target.last
            { 'target' => name, 'version' => version }
        }

        workflows_to_create = []
        RELEASE::RELEASE_XCODE_CLOUD_TARGETS.each { |name, filter|
            RELEASE::XCODE_VERSIONS.each { |version|
                if filter.call(version)
                    workflow = { "target" => name, "version" => version }
                    unless current_workflows.include? workflow
                        workflows_to_create.append(workflow)
                    end
                end
            }
        }

        workflows_to_create.each { |workflow|
            name = workflow['target']
            version = workflow['version']
            puts "Creating new workflow for target: #{name} and version #{version} for release"
            workflow_id = create_workflow(name, version, 'release_')
        }
    else
        puts "No"
    end
end

def delete_unused_workflows
    if !ENV.include?('CI')
        print "Are you sure you want to clear unused workflow?, this will delete not-declared local workflows that may be currently working in other PRs [Y/N]\n"
        user_input = STDIN.gets.chomp.downcase
    else 
        user_input = 'y'
    end
    
    if user_input == "y"
        local_workflows = []
        WORKFLOWS::TARGETS.each { |name, filter|
            WORKFLOWS::XCODE_VERSIONS.each { |version|
                if filter.call(version)
                    local_workflows.append("#{name}_#{version}")
                end
            }
        }

        remote_workflows = get_workflows
        remote_workflows.each.map { |workflow| 
            if workflow["attributes"]["name"].include? "release"
                return nil
            end

            name = workflow["attributes"]["name"]
            unless local_workflows.include? name
                puts "Deleting unused workflow #{workflow["id"]} #{name}"
                delete_workflow(workflow["id"])
            end
        }
    else
        puts "No"
    end
end

def delete_unused_release_workflows
    if !ENV.include?('CI')
        print "Are you sure you want to clear unused workflow?, this will delete not-declared local workflows that may be currently working in other PRs [Y/N]\n"
        user_input = STDIN.gets.chomp.downcase
    else 
        user_input = 'y'
    end
    
    if user_input == "y"
        local_workflows = ["release_package-docs_#{RELEASE::DOCS_XCODE_VERSION}"]
        RELEASE::RELEASE_XCODE_CLOUD_TARGETS.each { |name, filter|
            RELEASE::XCODE_VERSIONS.each { |version|
                if filter.call(version)
                    local_workflows.append("release_#{name}_#{version}")
                end
            }
        }

        remote_workflows = get_workflows
        .filter { |workflow| 
            workflow["attributes"]["name"].split('_').first == 'release' 
        }
        .map { |workflow| 
            name = workflow["attributes"]["name"]
            unless local_workflows.include? name
                puts "Deleting unused release workflow #{workflow["id"]} #{name}"
                delete_workflow(workflow["id"])
            end
        }
          
    else
        puts "No"
    end
end

def get_action_for_target(name)
    workflow_id = get_workflow_id_for_name(name)
    if workflow_id.nil?
        get_new_action_for_target(name)
    else
        workflow_info = get_workflow_info(workflow_id)
        result = JSON.parse(workflow_info)
        build_action = result["data"]["attributes"]["actions"]
        return build_action
    end
end 

def get_new_action_for_target(name)
    target_split = name.split('-')
    platform = target_split[0]
    target = target_split[1]

    name = ''
    build_platform = ''
    test_destination = ''
    case platform
    when 'osx'
        name = 'Test - macOS'
        build_platform = 'MACOS'
        test_destination = {
            "deviceTypeName" => "Mac",
            "deviceTypeIdentifier" => "mac",
            "runtimeName" => "Same As Selected macOS Version",
            "runtimeIdentifier" => "builder",
            "kind" => "MAC"
        }
    when 'catalyst'
        name = 'Test - macOS (Catalyst)'
        build_platform = 'MACOS'
        test_destination = {
            "deviceTypeName" => "Mac (Mac Catalyst)",
            "deviceTypeIdentifier" => "mac_catalyst",
            "runtimeName" => "Same As Selected macOS Version",
            "runtimeIdentifier" => "builder",
            "kind" => "MAC"
        }
    when 'ios'
        name = 'Test - iOS'
        build_platform = 'IOS'
        test_destination = {
            "deviceTypeName" => "iPhone 11",
            "deviceTypeIdentifier" => "com.apple.CoreSimulator.SimDeviceType.iPhone-11",
            "runtimeName" => "Latest from Selected Xcode (iOS 16.1)",
            "runtimeIdentifier" => "default",
            "kind" => "SIMULATOR"
        }
    when 'tvos'
        name = 'Test - tvOS'
        build_platform = 'TVOS'
        test_destination = {
            "deviceTypeName" => "Recommended Apple TVs",
            "deviceTypeIdentifier" =>  "recommended_apple_tvs",
            "runtimeName" =>  "Latest from Selected Xcode (tvOS 16.4)",
            "runtimeIdentifier" =>  "default",
            "kind" =>  "SIMULATOR"
        }
    else #docs, swiftlint, cocoapods, swiftpm, spm, xcframework, objectserver, watchos
        return [{
            "name" =>  "Build - macOS",
            "actionType" => "BUILD",
            "destination" => "ANY_MAC",
            "buildDistributionAudience" => nil,
            "testConfiguration" => nil,
            "scheme" => "CI",
            "platform" => "MACOS",
            "isRequiredToPass" => true
        }]
    end

    scheme = case target
    when 'swift'
        "RealmSwift"
    when 'swiftui'
        "SwiftUITests"
    when 'swiftuiserver'
        "SwiftUISyncTests"
    else
        "Realm"
    end

    return [{
        "name" => name,
        "actionType" => "TEST",
        "destination" => nil,
        "buildDistributionAudience" => nil,
        "testConfiguration" => {
            "kind" => "USE_SCHEME_SETTINGS",
            "testPlanName" => "",
            "testDestinations" => [ test_destination ]
        },
        "scheme" => scheme,
        "platform" => build_platform,
        "isRequiredToPass" => true
    }]
end 

def get_xcode_id(version)
    list_xcodeversion = ''
    if $xcode_list != ''
        list_xcodeversion = $xcode_list
    else 
        list_xcodeversion = get_xcode_versions
        $xcode_list = list_xcodeversion
    end

    list_xcodeversion.each do |xcode|
        if xcode["name"].include? "#{version}"
            return xcode["id"]
        end
    end
end

def get_macos_latest_release(xcodeVersionId)
    list_macosversion = ''
    if $mac_dict[xcodeVersionId] == ''
        list_macosversion = $mac_dict[xcodeVersionId]
    else 
        list_macosversion = get_macos_versions_for_xcode_version(xcodeVersionId)
        $mac_dict[xcodeVersionId] = list_macosversion
    end
    list_macosversion.each do |mac_os, id|
        if mac_os.include? "Latest Release"
            return id
        end
    end
end

def get_realm_product_id
    if $product_id != ''
        return $product_id
    end
    product = get_products
    product.each do |product|
        if product["product"] == "RealmSwift"
            $product_id = product["id"]
            return product["id"]
        end
    end
end

def get_realm_repository_id
    if $repository_id != ''
        return $repository_id
    end
    repositories = get_repositories
    repositories.each do |repo|
        if repo["name"] == "realm-swift"
            $repository_id = repo["id"]
            return repo["id"]
        end
    end
end

def get_workflow_id_for_name(name)
    workflows = ''
    if $workflows_list != ''
        workflows = $workflows_list
    else 
        workflows = get_workflows
        $workflows_list = workflows
    end
    workflows.each do |workflow|
        if workflow["attributes"]["name"] == name
            return workflow["id"]
        end
    end
    return nil
end

def read_build_info(build_id)
    response = get("/ciBuildRuns/#{build_id}")
    return response.body
end

def run_release_workflow(name)
    puts "Running workflow #{name}"
    workflow_id = get_workflow_id_for_name(name)
    build_id = start_build(workflow_id) 
end

def check_status_and_wait(build_run)
    begin
        build_state = read_build_info(build_run)
        result = JSON.parse(build_state)
        status = result["data"]["attributes"]["executionProgress"]
        puts "Current status #{status}"
        puts 'Waiting'
        if status == 'COMPLETE'
            completed = true
        end
    end until completed == true or not sleep 20
    
    build_state = read_build_info(build_run)
    result = JSON.parse(build_state)
    completion_status = result["data"]["attributes"]["completionStatus"]
    if completion_status != 'SUCCEEDED'
       puts "Completion status #{completion_status}"
       raise "Error running build"
    end
    get_logs_for_build(build_run)
    return
end

def get_logs_for_build(build_run)
    actions = get_build_actions(build_run)
    artifacts = get_artifacts(actions[0]["id"])
    artifact_info = get_artifact_info(artifacts[0]["id"])
    result = JSON.parse(artifact_info)
    artifact_url = result["data"]["attributes"]["downloadUrl"]
    print_artifact_logs(artifact_url)
end

def check_workflow_execution_status(build_id)
    build_state = read_build_info(build_id)
    result = JSON.parse(build_state)
    status = result["data"]["attributes"]["executionProgress"]
    return status
end

def create_workflow_and_run(name, xcode_version, prefix)
    workflow_id = create_workflow(name, xcode_version, prefix)
    build_run = start_build(workflow_id)
    check_status_and_wait(build_run)
end

def print_artifact_logs(url)
    sh 'curl', '--output', 'logs.zip', "#{url}"
    sh 'unzip', "logs.zip"
    file_name = Dir["RealmSwift*/ci_post_clone.log"]
    text = File.readlines("#{file_name[0]}").map do |line|
        puts line
    end
end

opts = GetoptLong.new(
    [ '--help', '-h', GetoptLong::NO_ARGUMENT ],
    [ '--token', '-t', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--team-id', GetoptLong::OPTIONAL_ARGUMENT ],
    [ '--xcode-version', '-x', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--issuer-id', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--key-id', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--pk-path', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--prefix', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--list-workflows', GetoptLong::NO_ARGUMENT ],
    [ '--list-products', GetoptLong::NO_ARGUMENT ],
    [ '--list-repositories', GetoptLong::NO_ARGUMENT ],
    [ '--list-mac-versions', GetoptLong::NO_ARGUMENT ],
    [ '--list-xcode-versions', GetoptLong::NO_ARGUMENT ],
    [ '--info-workflow', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--create-workflow', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--update-workflow', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--delete-workflow', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--build-workflow', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--create-new-workflows', GetoptLong::NO_ARGUMENT ],
    [ '--create-new-release-workflows', GetoptLong::NO_ARGUMENT ],
    [ '--clear-unused-workflows', GetoptLong::NO_ARGUMENT ],
    [ '--clear-unused-release-workflows', GetoptLong::NO_ARGUMENT ],
    [ '--run-release-workflow', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--check-workflow-status', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--create-release-workflow-and-run', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--get-token', GetoptLong::NO_ARGUMENT ]
)

option = ''
name = ''
workflow_id = ''
build_id = ''
xcode_version = ''
issuer_id = ''
key_id = ''
pk_path = ''
release_workflow_name = ''
prefix = ''

opts.each do |opt, arg|
    if opt != '--token' && opt != '--xcode-version' && opt != '--issuer-id' && opt != '--key-id' && opt != '--pk-path' && opt != '--team-id'
        option = opt
    end
    case opt
        when '--help'
            puts <<-EOF
hello [OPTION] ...

-h, --help:
    show help

--token [token], -t [token]:
    Apple connect API token 

--team-id [team_id]:
    Apple connect Tealm ID, to be used to return the url to the created workflow

--xcode-version [xcode_version]:
    XCode version used to create a new workflow

--issuer-id [issuer_id]:
    Apple Connect API Issuer ID.

--key-id [key_id]:
    Apple Connect API Key ID.

--pk-path [pk_path]:
    Apple Connect API path to private key file.

--prefix [prefix]:
    Prefix name for a new workflow.

--list-workflows:
    Returns a list of current workflows for the RealmSwift product.

--list-products:
    Returns a list of products associated to the Apple Connect Store account.

--list-repositories:
    Returns a list of repositories integrated with XCode Cloud.

--list-mac-versions:
    Returns a list of available mac versions.

--list-xcode-versions:
    Returns a list of available xcode version.

--info-workflow [workflow_id]:
    Returns the infor the corresponding workflow.

--create-workflow [name]:
    Use with --xcode-version
    Create a new workflow with the corresponding name.

--update-workflow [workflow_id]:
    Updates workflow with the corresponding id.

--delete-workflow [workflow_id]:
    Delete the workflow with the corrresponding id.

--build-workflow [workflow_id]:
    Run a build for the corresponding workflow.

--create-new-workflows:
    Adds the missing workflows corresponding to the list of targets and xcode versions in `pr-ci-matrix.rb`.
    
--create-new-release-workflows
    Create new workflows for the release pipeline.
    
--clear-unused-workflows:
    Clear all unused workflows which are not in the list of targets and xcode versions in `pr-ci-matrix.rb`.

--clear-unused-release-workflows
    Clear all unused workflows for the release pipeline

--run-release-workflow
    Runs a release workflow

--check-workflow-status
    Check workflow status 

--create-release-workflow-and-run
    Creates a workflow, runs it and wait for it to finish

--get-token:
    Get Apple Connect Store API Token for local use.

            EOF
            exit
        when '--token'
            if arg == ''
                raise "Token is required to execute this"
            else
                JWT_BEARER = arg
            end
        when '--team-id'
            if arg != ''
                TEAM_ID = arg
            end
        when '--issuer-id'
            if arg != ''
                issuer_id = arg
            end
        when '--key-id'
            if arg != ''
                key_id = arg
            end
        when '--pk-path'
            if arg != ''
                pk_path = arg
            end
        when '--prefix'
            if arg != ''
                prefix = arg
            end
        when '--info-workflow'
            if arg != ''
                workflow_id = arg
            end
        when '--create-workflow', '--create-release-workflow-and-run'
            if arg != ''
                name = arg
            end
        when '--delete-workflow', '--info-workflow', '--build-workflow', '--update-workflow'
            if arg != ''
                workflow_id = arg
            end
        when '--xcode-version'
            if arg != ''
                xcode_version = arg
            end
        when '--run-release-workflow'
            if arg != ''
                release_workflow_name = arg
            end
        when '--check-workflow-status'
            if arg != ''
                build_id = arg
            end
    end
end

if JWT_BEARER == '' && option != '--get-token'
    raise 'Token is needed to run this.'
end

if option == '--list-workflows'
    puts get_workflows
elsif option == '--list-products'
    puts get_products
elsif option == '--list-repositories'
    puts get_repositories
elsif option == '--list-mac-versions'
    puts get_macos_versions
elsif option == '--list-xcode-versions'
    puts get_xcode_versions
elsif option == '--info-workflow'
    if workflow_id == ''
        raise 'Needs workflow id'
    else
        print_workflow_info(workflow_id)
    end
elsif option == '--create-workflow'
    if name == '' || xcode_version == ''
        raise 'Needs name and xcode version'
    else
        create_workflow(name, xcode_version, prefix)
    end
elsif option == '--update-workflow'
    if workflow_id == ''
        raise 'Needs workflow id'
    else
        update_workflow(workflow_id)
    end
elsif option == '--delete-workflow'
    if workflow_id == ''
        raise 'Needs workflow id'
    else
        delete_workflow(workflow_id)
    end
elsif option == '--build-workflow'
    if workflow_id == ''
        raise 'Needs workflow id'
    else
        start_build(workflow_id)
    end
elsif option == '--create-new-workflows'
    if TEAM_ID == ''
        raise 'Needs team id'
    else
        create_new_workflows
    end
elsif option == '--create-new-release-workflows'
    if TEAM_ID == ''
        raise 'Needs team id'
    else
        create_new_release_workflows
    end
elsif option == '--clear-unused-workflows'
    delete_unused_workflows
elsif option == '--clear-unused-release-workflows'
    delete_unused_release_workflows
elsif option == '--get-token'
    if issuer_id == '' || key_id == '' || pk_path == ''
        raise 'Needs issuer id, key id or pk id.'
    else
        get_jwt_bearer(issuer_id, key_id, pk_path)
    end
elsif option == '--run-release-workflow'
    if  release_workflow_name == ''
        raise 'Needs workflow name to run.'
    else
        run_release_workflow(release_workflow_name)
    end
elsif option == '--check-workflow-status'
    if  build_id == ''
        raise 'Needs build id name to run.'
    else
        check_workflow_execution_status(build_id)
    end
elsif option == '--create-release-workflow-and-run'
    if name == '' || xcode_version == ''
        raise 'Needs name and xcode version'
    else
        create_workflow_and_run(name, xcode_version, "release_")
    end
end
