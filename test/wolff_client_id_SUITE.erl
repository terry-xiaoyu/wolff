%% Observe the client ID on the wire through wolff's public connectivity API.
-module(wolff_client_id_SUITE).
-compile(export_all).
-compile(nowarn_export_all).
-include_lib("eunit/include/eunit.hrl").

all() -> [configured_client_id, default_client_id].
init_per_suite(Config) ->
  {ok, Apps} = application:ensure_all_started(wolff),
  [{apps, Apps} | Config].
end_per_suite(Config) ->
  lists:foreach(fun application:stop/1, lists:reverse(proplists:get_value(apps, Config))).
init_per_testcase(_, Config) ->
  {ok, Listener} = gen_tcp:listen(0, [binary, {packet,4}, {active,false}, {ip,{127,0,0,1}}]),
  {ok, Port} = inet:port(Listener),
  Owner = self(),
  Broker = spawn_link(fun() ->
      {ok, Sock} = gen_tcp:accept(Listener),
      {ok, <<18:16, 0:16, Corr:32, Len:16, ClientId:Len/binary>>} = gen_tcp:recv(Sock, 0, 5000),
      Owner ! {client_id, ClientId},
      ok = gen_tcp:send(Sock, <<Corr:32, 0:16, 0:32>>),
      receive stop -> gen_tcp:close(Sock) end
    end),
  [{listener, Listener}, {port, Port}, {broker, Broker} | Config].
end_per_testcase(_, Config) ->
  proplists:get_value(broker, Config) ! stop,
  gen_tcp:close(proplists:get_value(listener, Config)).
configured_client_id(Config) ->
  probe(<<"internal-client">>, #{client_id => <<"wire-client">>}, <<"wire-client">>, Config).
default_client_id(Config) ->
  probe(<<"default-client">>, #{}, <<"default-client">>, Config).
probe(ClientId, ClientConfig, Expected, Config) ->
  Hosts = [{"127.0.0.1", proplists:get_value(port, Config)}],
  {ok, Pid} = wolff:ensure_supervised_client(ClientId, Hosts, ClientConfig),
  try
    ok = wolff_client:check_connectivity(Pid),
    receive {client_id, Value} -> ?assertEqual(Expected, Value)
    after 5000 -> ct:fail(no_kafka_request) end,
    ?assertEqual(ClientId, wolff_client:get_id(Pid)),
    ?assertEqual({ok, Pid}, wolff_client_sup:find_client(ClientId))
  after wolff:stop_and_delete_supervised_client(ClientId) end.
