# NOTICE
**This project is not supported anymore.**
It's still here just to support legacy projects that may have it as a dependency.
It's operational (at least, for Erlang versions lower than R17)
If you're looking for a HTTP client, we would recommend you to switch to [shotgun](https://github.com/inaka/shotgun) or [fusco](https://github.com/esl/fusco)

Dependencies:
 * Erlang/OTP R13-B or newer
   * Application compiler to build, kernel, stdlib and ssl to run

Building: 
For versions > 1.2.5, lhttpc is built using rebar. Take a look at http://bitbucket.org/basho/rebar/wiki/Home for more information. There is still a Makefile with some of the old make targets, such as all, doc, test etc. for those who prefer that. The makefile will however just call rebar.

Configuration: (environment variables)
 * connection_timeout: The time (in milliseconds) the client will try to
                       kepp a HTTP/1.1 connection open. Changing this value
                       in runtime has no effect, this can however be done
                       through lhttpc_manager:update_connection_timeout/1.
