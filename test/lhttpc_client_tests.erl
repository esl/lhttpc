%%%=============================================================================
%%% @copyright (C) 1999-2012, Erlang Solutions Ltd
%%% @author Diana Corbacho <diana.corbacho@erlang-solutions.com>
%%% @doc Unit tests for lhttpc_client
%%% @end
%%%=============================================================================
-module(lhttpc_client_tests).
-copyright("2012, Erlang Solutions Ltd.").

-include_lib("eunit/include/eunit.hrl").

-compile(export_all).

fail_connect_test() ->
    ?assertEqual({error, connection_closed},
		 lhttpc_client:start({{"localhost", 8080, false}, []}, [])).

fail_connect_pool_test() ->
    ?assertEqual({error, unknown_pool},
		 lhttpc_client:start({{"localhost", 8080, false},
				      [{pool, my_test_pool}]}, [])).

success_connect_pool_test_() ->
    {setup,
     fun() ->
	     ok = application:start(ssl),
	     ok = application:start(lhttpc)
     end,
     fun(_) ->
	     application:stop(lhttpc)
     end,
     fun() ->
	     ?assertMatch({error, connection_closed},
			  lhttpc_client:start({{"localhost", 8080, false},
					       [{pool, my_test_pool},
						{pool_ensure, true}]}, []))
     end
    }.
