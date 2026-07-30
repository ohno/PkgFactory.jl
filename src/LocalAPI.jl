"""
This module contains the API for the local environment using the [Git.jl](https://github.com/JuliaVersionControl/Git.jl) and [GitHub CLI](https://github.com/JuliaBinaryWrappers/gh_cli_jll.jl).
"""
module LocalAPI

# Packages

import DocStringExtensions
import Git
import gh_cli_jll

function hello()
    # return "Hello, LocalAPI.jl!"
    run(`$(Git.git()) --version`)
    return "Hello, LocalAPI.jl!"
end

# Functions

function check_status_code()
    return run(`$(gh_cli_jll.gh()) auth status`)
end

function login()
    return run(`$(gh_cli_jll.gh()) auth login`)
end

function _run_command(cmd::Cmd; env::Dict{String,String}=Dict{String,String}())
    out = IOBuffer()
    err = IOBuffer()
    process = run(pipeline(ignorestatus(setenv(cmd, env)), stdout=out, stderr=err))
    stdout = String(take!(out))
    stderr = String(take!(err))
    return success(process), stdout, stderr
end

function _run_command_or_throw(cmd::Cmd; env::Dict{String,String}=Dict{String,String}())
    ok, stdout, stderr = _run_command(cmd; env=env)
    ok || error("Command failed: $(cmd)\nSTDOUT:\n$(stdout)\nSTDERR:\n$(stderr)")
    return stdout
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function create_package_with_jll(
    access_token::String,
    owner_name::String,
    repo_name::String,
    author_names::Vector{String},
    package_description::String;
    commit_message::String = "Using PkgFactory.jl",
)
    gh_env = Dict("GH_TOKEN" => access_token)

    _run_command_or_throw(`$(gh_cli_jll.gh()) repo create $(owner_name)/$(repo_name) --public --description $(package_description) --homepage https://$(owner_name).github.io/$(repo_name) --confirm`; env=gh_env)

    pubkey, privkey = GitHub.genkeys()
    _run_command_or_throw(`$(gh_cli_jll.gh()) api repos/$(owner_name)/$(repo_name)/keys --method POST -f title=Documenter -f key=$(pubkey) -F read_only=false`; env=gh_env)
    _run_command_or_throw(`$(gh_cli_jll.gh()) secret set DEPLOY_KEY --repo $(owner_name)/$(repo_name) --body $(privkey)`; env=gh_env)

    main_ref = strip(_run_command_or_throw(`$(gh_cli_jll.gh()) api repos/$(owner_name)/$(repo_name)/git/ref/heads/main --jq .object.sha`; env=gh_env))
    _run_command_or_throw(`$(gh_cli_jll.gh()) api repos/$(owner_name)/$(repo_name)/git/refs --method POST -f ref=refs/heads/gh-pages -f sha=$(main_ref)`; env=gh_env)

    paths_and_contents = generate_template_dict(owner_name, repo_name, author_names, package_description)
    tempdir = mktempdir()

    _run_command_or_throw(`$(Git.git()) -C $(tempdir) init`)
    _run_command_or_throw(`$(Git.git()) -C $(tempdir) checkout -b main`)
    _run_command_or_throw(`$(Git.git()) -C $(tempdir) config user.name $(first(author_names))`)
    _run_command_or_throw(`$(Git.git()) -C $(tempdir) config user.email pkgfactory@example.com`)

    for (path, content) in paths_and_contents
        file_path = joinpath(tempdir, path)
        mkpath(dirname(file_path))
        write(file_path, content)
    end

    _run_command_or_throw(`$(Git.git()) -C $(tempdir) add .`)
    _run_command_or_throw(`$(Git.git()) -C $(tempdir) commit -m $(commit_message)`)

    _run_command_or_throw(`$(gh_cli_jll.gh()) auth setup-git`; env=gh_env)
    _run_command_or_throw(`$(Git.git()) -C $(tempdir) remote add origin https://github.com/$(owner_name)/$(repo_name).git`)
    _run_command_or_throw(`$(Git.git()) -C $(tempdir) push -u origin main`)

    return true
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function get_codecov_url(owner_name::String, repo_name::String)::String
    return "https://app.codecov.io/gh/$(owner_name)/$(repo_name)/new"
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function set_codecov(access_token::String, owner_name::String, repo_name::String, codecov_token::String)
    return set_repository_secret(access_token, owner_name, repo_name, "CODECOV_TOKEN", codecov_token)
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function set_deploy_key(access_token::String, owner_name::String, repo_name::String)
    # https://github.com/JuliaWeb/GitHub.jl?tab=readme-ov-file#ssh-keys
    pubkey, privkey = GitHub.genkeys()
    auth = GitHub.authenticate(access_token)
    repo = GitHub.repo("$(owner_name)/$(repo_name)"; auth = auth)
    try
        response1 = GitHub.create_deploykey(
            repo;
            auth = auth,
            params = Dict(
                "key" => pubkey,
                "title" => "Documenter",
                "read_only" => false,
                "handle_error" => false,
            ),
        )
        response2 = PkgFactory.set_repository_secret(access_token, owner_name, repo_name, "DEPLOY_KEY", privkey)
        if !isnothing(response1.id) && response2
            return true
        else
            return false
        end
    catch e
        return false
    end
end

function create_package(owner_name::String, repo_name::String, author_names::Vector{String}, package_description::String, codecov_token::String)
    check_name = PkgFactory.verify_package_name(repo_name)
    if check_name != "OK"
        return "Error: Package name is not valid: $(check_name)"
    end
    PkgFactory.create_repo(PERSONAL_ACCESS_TOKEN, owner_name, repo_name, package_description)
    PkgFactory.set_deploy_key(PERSONAL_ACCESS_TOKEN, owner_name, repo_name)
    PkgFactory.get_codecov_url(owner_name, repo_name)
    PkgFactory.set_codecov(PERSONAL_ACCESS_TOKEN, owner_name, repo_name, codecov_token)    
    PkgFactory.create_branch_gh_pages(PERSONAL_ACCESS_TOKEN, owner_name, repo_name)
    paths_and_contents = PkgFactory.generate_template_dict(owner_name, repo_name, author_names, package_description)
    PkgFactory.commit_files_on_github(PERSONAL_ACCESS_TOKEN, owner_name, repo_name, "main", "Using PkgFactory.jl", paths_and_contents)
    return "Success: $(repo_name) is created"
end

end
