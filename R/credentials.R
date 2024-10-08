#' @importFrom openssl write_ssh write_pem write_pkcs1 write_openssh_pem
#' @importFrom credentials ssh_key_info git_credential_forget ssh_read_key
#' @importFrom askpass askpass
make_key_cb <- function(ssh_key = NULL, host = NULL, password = askpass){
  function(){
    try({
      if(is.null(ssh_key)){
        ssh_key <- try(ssh_key_info(host = host, auto_keygen = FALSE)$key)
        if(inherits(ssh_key, "try-error"))
          return(NULL)
      }
      key <- tryCatch(ssh_read_key(ssh_key, password = password), error = function(e){
        stop(sprintf("Unable to load key: %s", ssh_key), call. = FALSE)
      })
      # NB: need to add ID for buggy libssh2: https://github.com/libgit2/libgit2/issues/5162
      writeLines(paste(write_ssh(key$pubkey), "git@localhost"), tmp_pub <- tempfile())

      # NB: pkcs1 is the only format that works on all libssh2 configurations
      tmp_key <- if(inherits(key, c("rsa", "dsa", "ecdsa"))){
        write_pkcs1(key, tempfile())
      } else {
        write_openssh_pem(key, tempfile())
      }
      if(.Platform$OS.type == "unix"){
        Sys.chmod(tmp_pub, '0644')
        Sys.chmod(tmp_key, '0400')
      }
      c(tmp_pub, tmp_key, "")
    })
  }
}

#' @importFrom credentials git_credential_ask
make_cred_cb <- function(password = askpass, verbose = TRUE){
  if(!is.character(password) && !is.function(password)){
    stop("Password parameter must be string or callback function")
  }
  function(url, username, retries){
    # Case of hardcoded (string) password
    if(is.character(password)){
      if(!length(username) || is.na(username)){
        stop("To use a hardcoded password, include your username in the URL like 'https://jerry@github.com")
      }
      return(c(username, password))
    }

    # Look for GITHUB_PAT variable
    if(retries < 2){
      github_pat <- Sys.getenv('GITHUB_PAT')
      if(nchar(github_pat) > 0 && grepl('^https?://([^/]*@)?github.com', url)){
        return(c("git", github_pat))
      }
    }

    # Retrieve a password from the credential manager
    if(retries > 2){
      try(git_credential_forget(url))
    }
    cred <- try(git_credential_ask(url, verbose = verbose), silent = !verbose)
    if(inherits(cred, 'git_credential')){
      return(c(cred$username, cred$password))
    }

    # If that doesn't work try to manually prompt
    if(!length(username) || is.na(username)){
      password(sprintf("Please enter username for %s", url))
    }
    pwd <- password(sprintf("Please enter a PAT or password for %s", url))
    as.character(c(username, pwd))
  }
}

remote_to_host <- function(repo, remote){
  rms <- git_remote_list(repo = repo)
  url <- rms[rms$name == remote, ]$url
  if(length(url)){
    url_to_host(url)
  }
}

url_to_host <- function(url){
  #credentials:::parse_url(url, allow_ssh = TRUE)[['host']]
  parse_url <- utils::getFromNamespace('parse_url', 'credentials')
  parse_url(url, allow_ssh = TRUE)[['host']]
}
