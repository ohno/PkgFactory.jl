"""
This module contains the interactive command-line interface for the local environment.
"""
module LocalUI

# Packages

import ..LocalAPI
import ..Templates
import ..Verifications
import DocStringExtensions

function hello()
    return "Hello, LocalUI.jl!"
end

# Functions

function _read_line(
    input::IO,
    output::IO,
    message::String;
    default::Union{Nothing,String} = nothing,
    example::Union{Nothing,String} = nothing,
)
    annotation = if !isnothing(default)
        " (default: $(default))"
    elseif !isnothing(example)
        " (example: $(example))"
    else
        ""
    end
    suffix = "$(annotation): "
    print(output, message, suffix)
    flush(output)
    eof(input) && error("Input ended while waiting for: $(message)")
    value = String(strip(readline(input)))
    return isempty(value) && !isnothing(default) ? default : value
end

function _prompt_value(
    input::IO,
    output::IO,
    message::String;
    default::Union{Nothing,String} = nothing,
    example::Union{Nothing,String} = nothing,
    validator = value -> isempty(value) ? "This value must not be empty." : "OK",
)
    while true
        value = _read_line(input, output, message; default = default, example = example)
        validation = validator(value)
        validation == "OK" && return value
        println(output, "Invalid input: $(validation)")
    end
end

function _prompt_yes_no(
    input::IO,
    output::IO,
    message::String;
    default::Union{Nothing,Bool} = nothing,
    example::String = "y",
)::Bool
    annotation = if isnothing(default)
        "example: $(example)"
    else
        "default: $(default ? "y" : "n")"
    end
    suffix = " ($(annotation)) (y/n): "
    while true
        print(output, message, suffix)
        flush(output)
        eof(input) && error("Input ended while waiting for: $(message)")
        answer = lowercase(strip(readline(input)))
        isempty(answer) && !isnothing(default) && return default
        answer in ["y", "yes"] && return true
        answer in ["n", "no"] && return false
        println(output, "Please answer y or n.")
    end
end

function _read_secret(input::IO, output::IO, message::String)::String
    if input isa Base.TTY && input === stdin
        secret = read(Base.getpass(input, output, message), String)
        println(output)
        return strip(secret)
    end
    return _read_line(input, output, message)
end

function _prompt_secret(
    input::IO,
    output::IO,
    message::String;
    example::Union{Nothing,String} = nothing,
    required::Bool = true,
    secret_reader = _read_secret,
)::String
    annotations = String[]
    !required && push!(annotations, "optional")
    !isnothing(example) && push!(annotations, "example: $(example)")
    annotation = isempty(annotations) ? "" : " ($(join(annotations, ", ")))"
    prompt = "$(message)$(annotation)"
    while true
        secret = secret_reader(input, output, prompt)
        (!required || !isempty(secret)) && return secret
        println(output, "Invalid input: This value must not be empty.")
    end
end

function _parse_author_names(value::String)::Vector{String}
    return filter(name -> !isempty(name), strip.(split(value, ',')))
end

function _suggest_package_names(
    repo_name::String,
    repository_names::Vector{String};
    count::Int = 3,
)::Vector{String}
    count > 0 || return String[]
    package_name = LocalAPI._get_package_name(repo_name)
    numbered_name = match(r"^(.*?)(\d+)$", package_name)
    base_name = isnothing(numbered_name) ? package_name : String(numbered_name.captures[1])
    existing_names = Set(lowercase.(repository_names))
    suffix_pattern = Regex("^$(base_name)(\\d+)\\.jl\$", "i")
    existing_suffixes = BigInt[]
    for repository_name in repository_names
        suffix_match = match(suffix_pattern, repository_name)
        isnothing(suffix_match) ||
            push!(existing_suffixes, parse(BigInt, suffix_match.captures[1]))
    end
    requested_suffix =
        isnothing(numbered_name) ? big(0) : parse(BigInt, numbered_name.captures[2])
    largest_suffix = isempty(existing_suffixes) ? big(0) : maximum(existing_suffixes)
    suffix = max(requested_suffix, largest_suffix) + 1
    suggestions = String[]

    while length(suggestions) < count
        suggestion = "$(base_name)$(suffix)"
        lowercase("$(suggestion).jl") in existing_names || push!(suggestions, suggestion)
        suffix += 1
    end
    return suggestions
end

function _prompt_suggested_package_name(
    input::IO,
    output::IO,
    suggestions::Vector{String},
)::String
    isempty(suggestions) && error("No package name suggestions are available.")
    println(output, "Available package name suggestions:")
    for (index, suggestion) in enumerate(suggestions)
        default_label = index == 1 ? " (default)" : ""
        println(output, "  $(index). $(suggestion)$(default_label)")
    end

    while true
        selection = _read_line(
            input,
            output,
            "Select a suggestion or enter another package name";
            default = "1",
            example = "2",
        )
        index = tryparse(Int, selection)
        if !isnothing(index)
            index in eachindex(suggestions) &&
                return LocalAPI._normalize_repo_name(suggestions[index])
            println(output, "Invalid input: Select one of the listed suggestions.")
            continue
        end

        package_name = LocalAPI._get_package_name(selection)
        validation = Verifications.verify_package_name(package_name)
        validation == "OK" && return LocalAPI._normalize_repo_name(selection)
        println(output, "Invalid input: $(validation)")
    end
end

function _prompt_package_name(
    input::IO,
    output::IO,
    owner_name::String;
    repository_checker,
    repository_names_provider,
)
    repo_name = _prompt_value(
        input,
        output,
        "Package name";
        example = "MyPkg",
        validator = value ->
            Verifications.verify_package_name(LocalAPI._get_package_name(value)),
    )
    repo_name = LocalAPI._normalize_repo_name(repo_name)
    known_repository_names = String[]

    while repository_checker(owner_name, repo_name)
        println(output, "Repository $(owner_name)/$(repo_name) already exists.")
        _prompt_yes_no(input, output, "Resume its setup?"; default = false) &&
            return (repo_name = repo_name, resume = true)

        append!(known_repository_names, repository_names_provider(owner_name))
        push!(known_repository_names, repo_name)
        suggestions = _suggest_package_names(repo_name, unique(known_repository_names))
        repo_name = _prompt_suggested_package_name(input, output, suggestions)
    end

    return (repo_name = repo_name, resume = false)
end

function _prompt_template(input::IO, output::IO, template_names::Vector{String})::String
    isempty(template_names) && error("No package templates are available.")
    ordered_template_names = String[]
    for preferred_name in ("all-in-one", "simple", "minimum")
        preferred_name in template_names && push!(ordered_template_names, preferred_name)
    end
    append!(
        ordered_template_names,
        sort(filter(name -> name ∉ ordered_template_names, template_names)),
    )

    println(output, "Package templates available:")
    for (index, template_name) in enumerate(ordered_template_names)
        default_label = index == 1 ? " (default)" : ""
        println(output, "  $(index). $(template_name)$(default_label)")
    end

    while true
        selection =
            _read_line(input, output, "Select template"; default = "1", example = "1")
        index = tryparse(Int, selection)
        !isnothing(index) &&
            index in eachindex(ordered_template_names) &&
            return ordered_template_names[index]

        matching_index = findfirst(==(selection), ordered_template_names)
        !isnothing(matching_index) && return ordered_template_names[matching_index]
        println(output, "Invalid input: Select one of the listed package templates.")
    end
end

function _prompt_visibility(input::IO, output::IO)::String
    visibilities = ["public", "private"]
    println(output, "Repository visibility:")
    for (index, visibility) in enumerate(visibilities)
        default_label = index == 1 ? " (default)" : ""
        println(output, "  $(index). $(visibility)$(default_label)")
    end

    while true
        selection =
            _read_line(input, output, "Select visibility"; default = "1", example = "2")
        index = tryparse(Int, selection)
        !isnothing(index) && index in eachindex(visibilities) && return visibilities[index]

        matching_index = findfirst(==(lowercase(selection)), visibilities)
        !isnothing(matching_index) && return visibilities[matching_index]
        println(output, "Invalid input: Select one of the listed visibility options.")
    end
end

function _prompt_repository_owner(input::IO, output::IO, owners)::String
    isempty(owners) && error("No GitHub account can create a repository.")
    println(output, "Repository owners available to the authenticated account:")
    for (index, owner) in enumerate(owners)
        kind = owner.kind == :user ? "personal account" : "organization"
        println(output, "  $(index). @$(owner.login) — $(owner.name) ($(kind))")
    end

    while true
        selection = _read_line(
            input,
            output,
            "Select repository owner";
            default = "1",
            example = "1",
        )
        index = tryparse(Int, selection)
        !isnothing(index) && index in eachindex(owners) && return owners[index].login

        matching_index =
            findfirst(owner -> lowercase(owner.login) == lowercase(selection), owners)
        !isnothing(matching_index) && return owners[matching_index].login
        println(output, "Invalid input: Select one of the listed repository owners.")
    end
end

function _print_summary(
    output::IO,
    owner_name::String,
    repo_name::String,
    author_names::Vector{String},
    package_description::String,
    template_name::String,
    visibility::String,
    commit_message::String,
    resume::Bool,
    codecov_configured::Bool,
)
    println(output, "\nPackage configuration")
    println(output, "  Repository:  $(owner_name)/$(repo_name)")
    println(output, "  Authors:     $(join(author_names, ", "))")
    println(output, "  Description: $(package_description)")
    println(output, "  Template:    $(template_name)")
    println(output, "  Visibility:  $(visibility)")
    println(output, "  Commit:      $(commit_message)")
    println(output, "  Resume:      $(resume ? "yes" : "no")")
    println(output, "  Codecov:     $(codecov_configured ? "configured" : "skipped")")
    return nothing
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

Start an interactive command-line workflow that collects package settings and delegates repository creation to [`PkgFactory.LocalAPI.create_package_with_jll`](@ref).

```
PkgFactory.LocalUI.CLI()
```
"""
function CLI(;
    input::IO = stdin,
    output::IO = stdout,
    environment::AbstractDict = ENV,
    status_checker = LocalAPI.check_status_code,
    login_handler = LocalAPI.login,
    package_creator = LocalAPI.create_package_with_jll,
    repository_checker = LocalAPI.check_repo,
    repository_names_provider = LocalAPI.get_repository_names,
    repository_owners_provider = LocalAPI.get_repository_owners,
    templates_provider = Templates.list_templates,
    secret_reader = _read_secret,
)::Bool
    println(output, "PkgFactory local package setup")
    println(output, "Follow the prompts to create a Julia package repository.\n")

    if !status_checker()
        println(output, "GitHub CLI is not authenticated.")
        _prompt_yes_no(input, output, "Log in to GitHub now?"; default = true) || begin
            println(output, "Cancelled: GitHub authentication is required.")
            return false
        end
        login_handler() || begin
            println(output, "GitHub authentication failed.")
            return false
        end
    end

    owners = try
        repository_owners_provider()
    catch e
        println(output, "Failed to load repository owners: $(sprint(showerror, e))")
        return false
    end
    owner_name = _prompt_repository_owner(input, output, owners)
    package_selection = try
        _prompt_package_name(
            input,
            output,
            owner_name;
            repository_checker = repository_checker,
            repository_names_provider = repository_names_provider,
        )
    catch e
        println(output, "Failed to check package name availability: $(sprint(showerror, e))")
        return false
    end
    repo_name = package_selection.repo_name
    resume = package_selection.resume

    author_text = _prompt_value(
        input,
        output,
        "Authors (comma-separated; written to LICENSE)";
        example = "Alice Smith, Bob Jones",
        validator = value ->
            isempty(_parse_author_names(value)) ? "At least one author is required." : "OK",
    )
    author_names = _parse_author_names(author_text)

    package_description = _prompt_value(
        input,
        output,
        "Package description";
        example = "Tools for data analysis",
    )
    template_names = try
        templates_provider()
    catch e
        println(output, "Failed to load package templates: $(sprint(showerror, e))")
        return false
    end
    template_name = _prompt_template(input, output, template_names)
    visibility = _prompt_visibility(input, output)
    commit_message = _prompt_value(
        input,
        output,
        "Initial commit message";
        default = "Using PkgFactory.jl",
    )
    codecov_token = String(strip(string(get(environment, "CODECOV_TOKEN", ""))))
    if isempty(codecov_token)
        println(output, "\nHow to get a Codecov upload token:")
        println(output, "  1. Sign in at https://app.codecov.io/.")
        println(
            output,
            "  2. Open $(owner_name) Settings > Global Upload Token and copy the token.",
        )
        println(output, "     Account owner or organization administrator access is required.")
        println(output, "  Guide: https://docs.codecov.com/docs/codecov-tokens")
        codecov_token = _prompt_secret(
            input,
            output,
            "Codecov token";
            example = "01234567-89ab-cdef-0123-456789abcdef",
            required = false,
            secret_reader = secret_reader,
        )
        codecov_token = String(strip(codecov_token))
    else
        println(output, "Using the Codecov token from CODECOV_TOKEN.")
    end

    _print_summary(
        output,
        owner_name,
        repo_name,
        author_names,
        package_description,
        template_name,
        visibility,
        commit_message,
        resume,
        !isempty(codecov_token),
    )
    _prompt_yes_no(input, output, "Create this repository?") || begin
        println(output, "Cancelled: no repository was created.")
        return false
    end

    println(output, "\nCreating $(owner_name)/$(repo_name)...")
    try
        created = package_creator(
            owner_name,
            repo_name,
            author_names,
            package_description,
            codecov_token;
            template_name = template_name,
            visibility = visibility,
            commit_message = commit_message,
            resume = resume,
        )
        created || error("The local API did not complete the package setup.")
    catch e
        println(output, "Failed: $(sprint(showerror, e))")
        return false
    end

    println(output, "Created: https://github.com/$(owner_name)/$(repo_name)")
    return true
end

end
