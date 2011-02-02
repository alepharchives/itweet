%%%-------------------------------------------------------------------
%%% @author Fernando Benavides <fernando.benavides@inakanetworks.com>
%%% @copyright (C) 2011 Inaka Labs SRL
%%% @doc Generic twitter stream client
%%%
%%% The user module should export:
%%%<ul>
%%%   <li>
%%%   <pre>init(Args::term()) -> init_result()</pre>
%%%     Opens and/or initializes the client.<br/>
%%%   </li><li>
%%%   <pre>handle_status(Status::json_object(), State::term()) -> handler_result()</pre>  
%%%     Called each time an status is received from twitter<br/>
%%%   </li><li>
%%%   <pre>handle_event(Event::atom(), Data::json_object(), State::term()) -> handler_result()</pre>
%%%     Called each time an event is received from twitter<br/>
%%%   </li><li>
%%%   <pre>handle_call(Msg::term(), From::reference(), State::term()) -> call_result() </pre>
%%%     Called from <code>itweep:call/2</code><br/>
%%%   </li><li>
%%%   <pre>handle_info(Msg::term(), State::term()) -> handler_result()</pre>
%%%     Called each time an erlang message is received<br/>
%%%   </li><li>
%%%   <pre>terminate(Reason :: normal | shutdown | term(), State) -> _</pre>
%%%     Let the user module clean up. Always called when server terminates.<br/>
%%%   </li></ul>
%%% @end
%%%-------------------------------------------------------------------

%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.

-module(itweep).
-author('Fernando Benavides <fernando.benavides@inakanetworks.com>').

-behaviour(gen_server).

%% @type gen_start_option() = {timeout, non_neg_integer() | infinity | hibernate} |
%%                            {debug, [trace | log | {logfile, string()} | statistics | debug]}. Generic start options (derived from gen_server)
%% @type required_option() = {user, string()}
%%                         | {password, string()}
%% @type start_option() = required_option()
%%                      | gen_start_option(). <b>itweep</b> start options (taken from the Twitter Stream API)
%% @type start_result() = {ok, pid()} | {error, {already_started, pid()}} | {error, term()}
-type gen_start_option() :: {timeout, non_neg_integer() | infinity | hibernate} |
                            {debug, [trace | log | {logfile, string()} | statistics | debug]}.
-type start_option() :: {user, string()} | {password, string()} | gen_start_option().
-type start_result() :: {ok, pid()} | {error, {already_started, pid()}} | {error, term()}.
-export_type([gen_start_option/0, start_option/0, start_result/0]).

%% @type init_result()     = {ok, State::term()} | ignore | {stop, Reason::term()}
%% @type handler_result()  = {ok, State::term()} | {stop, Reason::term(), State::term()}
%% @type call_result()     = {ok, Reply::term(), State::term()} | {stop, Reason::term(), Reply::term(), State::term()}
-type init_result()     :: {ok, State::term()} | ignore | {stop, Reason::term()}.
-type handler_result()  :: {ok, State::term()} | {stop, Reason::term(), State::term()}.
-type call_result()     :: {ok, Reply::term(), State::term()} | {stop, Reason::term(), Reply::term(), State::term()}.
-export_type([init_result/0, handler_result/0, call_result/0]).

%% @type server() = atom() | pid() | {global, atom()}. Server identification for calls
%% @type location() = {float(), float(), float(), float()}. Locations like the ones accepted by the Twitter Stream API
%% @type gen_option() = {count, integer()}. Options for firehose/2, links/2
%% @type filter_option() = gen_option() | {follow, [pos_integer()]}
%%                       | {track, [string()]} | {locations, [location()]}. Options for filter/2
-type server() :: atom() | pid() | {global, atom()}.
-type location() :: {float(), float(), float(), float()}.
-type gen_option() :: {count, -150000..150000}.
-type filter_option() :: gen_option() | {follow, [pos_integer()]}
                       | {track, [string()]} | {locations, [location()]}.
-export_type([server/0, location/0, filter_option/0]).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% EXPORTS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% BEHAVIOUR
-export([behaviour_info/1]).
%% API
-export([start/3, start/4, start_link/3, start_link/4, call/2, call/3]).
-export([filter/2, firehose/2, retweet/2, links/2, sample/2]).
-export([current_method/1]).
%% GEN SERVER
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% INTERNALS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-record(state, {module      :: atom(), % Callback module
                mod_state   :: term(), % Callback module state
                user        :: string(),
                password    :: string(),
                req_id      :: undefined | ibrowse:req_id(),
                buffer      :: binary(),
                http_status :: string(),
                http_headers:: [{string(), string()}],
                method= none:: none | {string(), [filter_option() | gen_option() | ibrowse:option()]} 
               }).
-opaque state() :: #state{}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% BEHAVIOUR FUNCTIONS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%% @hidden
-spec behaviour_info(callbacks | term()) -> undefined | [{atom(), non_neg_integer()}].
behaviour_info(callbacks) ->
  [{init, 1}, {handle_status, 2}, {handle_event, 3},
   {handle_info, 2}, {handle_call, 3}, {terminate, 2}];
behaviour_info(_Other) ->
  undefined.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% API FUNCTIONS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%% @doc  Starts a generic server.
%%% @spec start(Mod::atom(), Args::term(), Options::[start_option()]) ->
%%%         {ok, pid()} | {error, {already_started, pid()}} | {error, Reason::term()}
-spec start(Mod::atom(), Args::term(), Options::[start_option()]) -> start_result().
start(Mod, Args, Options) ->
  {User, Password, OtherOptions} = parse_start_options(Options),
  gen_server:start(?MODULE, {Mod, Args, User, Password}, OtherOptions).

%%% @doc  Starts a named generic server.
%%% @spec start(Name::{local | global, atom()}, Mod::atom(), Args::term(), Options::[start_option()]) ->
%%%         {ok, pid()} | {error, {already_started, pid()}} | {error, Reason::term()}
-spec start(Name::{local|global, atom()}, Mod::atom(), Args::term(), Options::[start_option()]) -> start_result().
start(Name, Mod, Args, Options) ->
  {User, Password, OtherOptions} = parse_start_options(Options),
  gen_server:start(Name, ?MODULE, {Mod, Args, User, Password}, OtherOptions).

%%% @doc  Starts and links a generic server.
%%% @spec start_link(Mod::atom(), Args::term(), Options::[start_option()]) ->
%%%         {ok, pid()} | {error, {already_started, pid()}} | {error, Reason::term()}
-spec start_link(Mod::atom(), Args::term(), Options::[start_option()]) -> start_result().
start_link(Mod, Args, Options) ->
  {User, Password, OtherOptions} = parse_start_options(Options),
  gen_server:start_link(?MODULE, {Mod, Args, User, Password}, OtherOptions).

%%% @doc  Starts and links a named generic server.
%%% @spec start_link(Name::{local | global, atom()}, Mod::atom(), Args::term(), Options::[start_option()]) ->
%%%         {ok, pid()} | {error, {already_started, pid()}} | {error, Reason::term()}
-spec start_link(Name::{local|global, atom()}, Mod::atom(), Args::term(), Options::[start_option()]) -> start_result().
start_link(Name, Mod, Args, Options) ->
  {User, Password, OtherOptions} = parse_start_options(Options),
  gen_server:start_link(Name, ?MODULE, {Mod, Args, User, Password}, OtherOptions).

%%% @doc  Starts using the statuses/filter method to get results
%%% @spec filter(server(), [filter_option() | ibrowse:option()]) -> ok
-spec filter(server(), [filter_option() | ibrowse:option()]) -> ok.
filter(Server, Options) ->
  gen_server:cast(Server, {"filter", Options}).

%%% @doc  Starts using the statuses/firehose method to get results
%%% @spec firehose(server(), [gen_option() | ibrowse:option()]) -> ok
-spec firehose(server(), [gen_option() | ibrowse:option()]) -> ok.
firehose(Server, Options) ->
  gen_server:cast(Server, {"firehose", Options}).

%%% @doc  Starts using the statuses/links method to get results
%%% @spec links(server(), [gen_option() | ibrowse:option()]) -> ok
-spec links(server(), [gen_option() | ibrowse:option()]) -> ok.
links(Server, Options) ->
  gen_server:cast(Server, {"links", Options}).

%%% @doc  Starts using the statuses/retweet method to get results
%%% @spec retweet(server(), [ibrowse:option()]) -> ok
-spec retweet(server(), [ibrowse:option()]) -> ok.
retweet(Server, Options) ->
  gen_server:cast(Server, {"retweet", Options}).

%%% @doc  Starts using the statuses/sample method to get results
%%% @spec sample(server(), [ibrowse:option()]) -> ok
-spec sample(server(), [ibrowse:option()]) -> ok.
sample(Server, Options) ->
  gen_server:cast(Server, {"sample", Options}).

%%% @doc Make a call to a generic server.
%%% If the server is located at another node, that node will be monitored.
%%% If the client is trapping exits and is linked server termination is handled here
%%% @spec call(Server::atom() | pid() | {global, atom()}, Request::term()) -> Response::term()
-spec call(Server::server(), Request::term()) -> Response::term().
call(Server, Request) ->
  gen_server:call(Server, {call, Request}).

%%% @doc Make a call to a generic server.
%%% If the server is located at another node, that node will be monitored.
%%% If the client is trapping exits and is linked server termination is handled here
%%% @spec call(Server::atom() | pid() | {global, atom()}, Request::term(), Timeout::non_neg_integer()|infinity) -> Response::term()
-spec call(Server::server(), Request::term(), Timeout::non_neg_integer()|infinity) -> Response::term().
call(Server, Request, Timeout) ->
  gen_server:call(Server, Request, Timeout).

%%% @doc Current method.
%%% Returns the current method and its parameters.
%%% @spec current_method(Server::atom() | pid() | {global, atom()}) -> none | {string(), [filter_option() | gen_option() | ibrowse:option()]}
-spec current_method(Server::atom() | pid() | {global, atom()}) -> none | {string(), [filter_option() | gen_option() | ibrowse:option()]}.
current_method(Server) ->
  gen_server:call(Server, current_method).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% GEN SERVER FUNCTIONS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @hidden
-spec init({atom(), term(), string(), string()}) -> {ok, #state{}} | ignore | {stop, term()}.
init({Mod, InitArgs, User, Password}) ->
  case Mod:init(InitArgs) of
    {ok, ModState} ->
      {ok, #state{module    = Mod,
                  mod_state = ModState,
                  user      = User,
                  password  = Password}};
    Other ->
      Other
  end.

%% @hidden
-spec handle_call(term(), reference(), state()) -> {reply, term(), state()} | {noreply, term()} | {stop, normal | shutdown | term(), term(), state()}.
handle_call(current_method, _From, State = #state{method = Method}) ->
  {reply, Method, State};
handle_call({call, Request}, From, State = #state{module = Mod, mod_state = ModState}) ->
  try Mod:handle_call(Request, From, ModState) of
    {ok, Reply, NewModSt} -> {reply, Reply, State#state{mod_state = NewModSt}};
    {stop, Reason, Reply, NewModSt} -> {stop, Reason, Reply, State#state{mod_state = NewModSt}}
  catch
    _:{ok, Reply, NewModSt} -> {reply, Reply, State#state{mod_state = NewModSt}};
    _:{stop, Reason, Reply, NewModSt} -> {stop, Reason, Reply, State#state{mod_state = NewModSt}}    
  end.

%% @hidden
-spec handle_cast({string(), [filter_option() | gen_option() | ibrowse:option()]}, #state{}) -> {noreply, #state{}}.
handle_cast(M = {Method, Options}, State = #state{user = User, password = Password, req_id = OldReqId}) ->
  BasicUrl = ["http://stream.twitter.com/1/statuses/", Method, ".json"],
  {Url, IOptions} = build_url(BasicUrl, Options),
  case connect(Url, IOptions, User, Password) of
    {ok, ReqId} ->
      stream_close(OldReqId),
      {noreply, State#state{req_id = ReqId, method = M}};
    {error, Reason} ->
      {stop, {error, Reason}, State}
  end.

%% @hidden
%% RESPONSE HEADERS --------------------------------------------------------------------------------
-spec handle_info(term(), state()) -> {noreply, state()} | {stop, term(), state()}.
handle_info({ibrowse_async_headers, ReqId, Code, Headers}, State = #state{req_id    = ReqId,
                                                                          module    = Mod,
                                                                          mod_state = ModState}) ->
  NewState =
    State#state{http_status = Code,
                http_headers= Headers,
                buffer      = <<>>},
  case run_handler(fun() -> Mod:handle_event(stream_start, null, ModState) end) of
    {ok, NewModSt} ->
      ok = ibrowse:stream_next(ReqId),
      {noreply, NewState#state{mod_state = NewModSt}};
    {stop, Reason, NewModSt} ->
      {stop, Reason, NewState#state{mod_state = NewModSt}}
  end;
handle_info({ibrowse_async_headers, _OldReqId, Code, Headers}, State) ->
  error_logger:warning_msg("~p - ~p: old req headers: ~p - ~p~n", [calendar:local_time(), ?MODULE, Code, Headers]),
  {noreply, State};
%% RESPONSE BODY -----------------------------------------------------------------------------------
handle_info({ibrowse_async_response, ReqId, {error, req_timedout}}, State = #state{req_id = ReqId}) ->
  error_logger:error_msg("~p - ~p: There're no more twitter results~n", [calendar:local_time(), ?MODULE]),
  {stop, normal, State};
handle_info({ibrowse_async_response, ReqId, {error, Error}}, State = #state{req_id = ReqId}) ->
  error_logger:error_msg("~p - ~p: Error querying twitter: ~p~n", [calendar:local_time(), ?MODULE, Error]),
  {stop, {error, Error}, State};
handle_info({ibrowse_async_response, ReqId, <<>>}, State = #state{req_id = ReqId}) ->
  {noreply, State};
handle_info({ibrowse_async_response, ReqId, <<$\n>>}, State = #state{req_id = ReqId}) ->
  {noreply, State};
handle_info({ibrowse_async_response, ReqId, Body}, State = #state{req_id      = ReqId,
                                                                  module      = Mod,
                                                                  http_status = "200",
                                                                  mod_state   = ModState,
                                                                  buffer      = Buffer}) ->
  case binary:split(Body, <<$\r>>, [global, trim]) of
    [Body] -> %% No \r
      ok = ibrowse:stream_next(ReqId),
      {noreply, State#state{buffer = <<Buffer/binary, $|, Body/binary>>}};
    [Head|Tail] ->
      RealBuffer = re:replace(Buffer, <<"\\|">>, <<>>, [global, {return, binary}]),
      {Jsons, NewBuffer} =
        try extract_jsons([<<RealBuffer/binary, Head/binary>> | Tail])
        catch
          _:{invalid_json, NoJson, Err} ->
            error_logger:error_msg("~n~p: INVALID JSON:~n\t~p~n~n\t~s~n~n\t~p~n~n", [?MODULE, Buffer, NoJson, Err])
        end,
      NewModSt =
       lists:foldl(
         fun(Json, AccModSt) ->
                 Fun = case Json of
                         {[{Event, Data}]} ->
                           fun() -> Mod:handle_event(binary_to_atom(Event, utf8),
                                                     Data, AccModSt)
                           end;
                         Status ->
                           fun() -> Mod:handle_status(Status, AccModSt) end
                       end,
                 case run_handler(Fun) of
                   {ok, NextModSt} -> NextModSt;
                   {stop, Reason, NextModSt} ->
                     throw({stop, Reason, State#state{mod_state = NextModSt}})
                 end
         end, ModState, Jsons),
      ok = ibrowse:stream_next(ReqId),
      {noreply, State#state{buffer = NewBuffer, mod_state = NewModSt}}
  end;
handle_info({ibrowse_async_response, ReqId, Body}, State = #state{req_id      = ReqId,
                                                                  buffer      = Buffer}) ->
  {noreply, State#state{buffer = <<Buffer/binary, Body/binary>>}};
handle_info({ibrowse_async_response, _OldReqId, {error, closing_on_request}}, State) ->
  {noreply, State};
handle_info({ibrowse_async_response, _OldReqId, Body}, State) ->
  error_logger:warning_msg("~p - ~p: old req response: ~p~n", [calendar:local_time(), ?MODULE, Body]),
  {noreply, State};
%% RESPONSE END ------------------------------------------------------------------------------------
handle_info({ibrowse_async_response_end, ReqId}, State = #state{req_id      = ReqId,
                                                                http_status = "200",
                                                                module      = Mod,
                                                                mod_state   = ModState}) ->
  case run_handler(fun() -> Mod:handle_event(stream_end, null, ModState) end) of
    {ok, NewModSt} ->
      {stop, normal, State#state{mod_state = NewModSt, req_id = undefined}};
    {stop, Reason, NewModSt} ->
      {stop, Reason, State#state{mod_state = NewModSt}}
  end;
handle_info({ibrowse_async_response_end, ReqId}, State = #state{req_id      = ReqId,
                                                                http_status = Code,
                                                                http_headers= Headers,
                                                                module      = Mod,
                                                                mod_state   = ModState,
                                                                buffer      = Buffer}) ->
  case run_handler(
         fun() ->
                 Mod:handle_event(stream_error, headers_to_json(Code, Headers, Buffer), ModState)
         end) of
    {ok, NewModSt} ->
      ok = ibrowse:stream_next(ReqId),
      {noreply, State#state{mod_state = NewModSt}};
    {stop, Reason, NewModSt} -> {stop, Reason, State#state{mod_state = NewModSt}}
  end;
handle_info({ibrowse_async_response_end, _OldReqId}, State) ->
  error_logger:info_msg("~p - ~p: old req end~n", [calendar:local_time(), ?MODULE]),
  {noreply, State};
%% OTHERs ------------------------------------------------------------------------------------------
handle_info(Info, State = #state{module = Mod, mod_state = ModState}) ->
  case run_handler(fun() -> Mod:handle_info(Info, ModState) end) of
    {ok, NewModSt} -> {noreply, State#state{mod_state = NewModSt}};
    {stop, Reason, NewModSt} -> {stop, Reason, State#state{mod_state = NewModSt}}
  end.

%% @hidden
-spec terminate(any(), #state{}) -> any().
terminate(Reason, #state{module = Mod, mod_state = ModState, req_id = ReqId}) ->
  stream_close(ReqId),
  Mod:terminate(Reason, ModState).

%% @hidden
-spec code_change(any(), any(), any()) -> {ok, any()}.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% PRIVATE FUNCTIONS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
parse_start_options(Options) ->
  User = case proplists:get_value(user, Options) of
           undefined -> throw({missing_option, user});
           U -> U
         end,
  Password = case proplists:get_value(password, Options) of
               undefined -> throw({missing_option, password});
               P -> P
             end,
  {User, Password, proplists:delete(user, proplists:delete(password, Options))}.

build_url(BasicUrl, Options) ->
  build_url(Options, $?, BasicUrl, []).
build_url([], _Sep, Url, Options) -> {lists:flatten(Url), Options};
build_url([{count, V} | Rest], Sep, Url, Ops) ->
  build_url(Rest, $&, [Url, Sep, "count=", integer_to_list(V)], Ops);
build_url([{delimited, length} | Rest], Sep, Url, Ops) ->
  build_url(Rest, $&, [Url, Sep, "delimited=length"], Ops);
build_url([{follow, V} | Rest], Sep, Url, Ops) ->
  Users =
    lists:foldl(fun(User, []) ->
                        integer_to_list(User);
                   (User, Acc) ->
                        Acc ++ [$, | integer_to_list(User)]
                end, [], V),
  build_url(Rest, $&, [Url, Sep, "follow=", Users], Ops);
build_url([{track, V} | Rest], Sep, Url, Ops) ->
  Terms =
    lists:foldl(fun(Term, []) -> Term;
                   (Term, Acc) -> Acc ++ [$, | Term]
                end, [], V),
  build_url(Rest, $&, [Url , Sep, "track=", Terms], Ops);
build_url([{locations, V} | Rest], Sep, Url, Ops) ->
  Locations =
    lists:foldl(fun({L1,L2,L3,L4}, []) ->
                        io_lib:format("~.5g,~.5g,~.5g,~.5g", [L1,L2,L3,L4]);
                   ({L1,L2,L3,L4}, Acc) ->
                        io_lib:format("~s,~.5g,~.5g,~.5g,~.5g", [Acc,L1,L2,L3,L4])
                end, [], V),
  build_url(Rest, $&, [Url, Sep, "locations=", Locations], Ops);
build_url([O|Rest], Sep, Url, Ops) ->
  build_url(Rest, Sep, Url, [O|Ops]).

stream_close(undefined) -> ok;
stream_close(OldReqId) ->
  ibrowse:stream_close(OldReqId).

run_handler(Fun) ->
  try Fun() of
    {ok, NewModSt} -> {ok, NewModSt};
    {stop, Reason, NewModSt} -> {stop, Reason, NewModSt};
    Other -> throw({bad_return, Other})
  catch
    _:{ok, NewModSt} -> {ok, NewModSt};
    _:{stop, Reason, NewModSt} -> {stop, Reason, NewModSt}
  end.

headers_to_json(Code, Headers, Body) ->
  {{code,     list_to_binary(Code)},
   {body,     Body},
   {headers,  lists:map(fun({K,V}) -> {list_to_binary(K), list_to_binary(V)} end, Headers)}}.

extract_jsons(Lines) ->
  extract_jsons(Lines, []).
extract_jsons([], Acc) ->
  {lists:reverse(Acc), <<>>};
extract_jsons([<<$\n>>], Acc) ->
  {lists:reverse(Acc), <<>>};
extract_jsons([NewBuffer], Acc) ->
  %%HACK: Even when Twitter Stream API docs say that...
  %%          ...every object is returned on its own line, and ends with a carriage return. Newline
  %%          characters (\n) may occur in object elements (the text element of a status object, for
  %%          example), but carriage returns (\r) should not.
  %%      ...sometimes they just don't send the \r after the last object
  try itweep_mochijson2:decode(NewBuffer) of
    Json ->
      {lists:reverse([Json|Acc]), <<>>}
  catch
    throw:{invalid_json, NewBuffer, _Err} ->
      {lists:reverse(Acc), NewBuffer}
  end;
extract_jsons([<<>> | Rest], Acc) ->
  extract_jsons(Rest, Acc);
extract_jsons([<<$\n>> | Rest], Acc) ->
  extract_jsons(Rest, Acc);
extract_jsons([Next | Rest], Acc) ->
  Json = itweep_mochijson2:decode(Next),
  extract_jsons(Rest, [Json | Acc]).

connect(Url, IOptions, User, Password) ->
  error_logger:info_msg("~p: Connecting to ~s...~n", [?MODULE, Url]),
  try ibrowse:send_req(Url, [], get, [], [{basic_auth, {User, Password}},
                                          {stream_to, {self(), once}},
                                          {response_format, binary} | IOptions], infinity) of
    {ibrowse_req_id, ReqId} ->
      {ok, ReqId};
    {ok, Status, _Headers, Body} ->
      error_logger:error_msg("~p - ~p: Error trying to connect with twitter:~n\t~s: ~s~n", [calendar:local_time(), ?MODULE, Status, Body]),
      {error, {Status, Body}};
    {error, Reason} ->
      error_logger:error_msg("~p - ~p: ibrowse error trying to connect with twitter:~n\t~s: ~s~n", [calendar:local_time(), ?MODULE, Reason]),
      {error, Reason}
  catch
    _:{timeout, _} -> %% An ibrowse internal process timed out
      error_logger:error_msg("~p - ~p: Internal timeout trying to connect with twitter~n", [calendar:local_time(), ?MODULE]),
      {error, internal_timeout};
    _:Error ->
      error_logger:error_msg("~p - ~p: System Error trying to connect with twitter:~n\t~p~n", [calendar:local_time(), ?MODULE, Error]),
      {error, Error}
  end.
