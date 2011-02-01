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

%% @type json_string() = atom() | binary(). JSON Strings
%% @type json_number() = integer() | float(). JSON Numbers
%% @type json_array()  = [json_term()]. JSON Arrays
%% @type json_object() = {[{json_string(), json_term()}]}. JSON Objects
%% @type json_boolean()= boolean(). JSON Booleans
%% @type json_null()   = null. JSON Null object
%% @type json_term()   = json_string() | json_number() | json_array() | json_object() | json_null() | json_boolean(). JSON Terms
-type json_string() :: atom() | binary().
-type json_number() :: integer() | float().
-type json_array()  :: [json_term()].
-type json_object() :: {[{json_string(), json_term()}]}.
-type json_boolean():: boolean().
-type json_null()   :: null.
-type json_term()   :: json_string() | json_number() | json_array() | json_object() | json_null() | json_boolean().
-export_type([json_string/0, json_number/0, json_array/0, json_object/0, json_boolean/0,
              json_null/0, json_term/0, gen_start_option/0, start_option/0, start_result/0]).

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
%% GEN SERVER
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% INTERNALS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-record(state, {module    :: atom(), % Callback module
                mod_state :: term(), % Callback module state
                user      :: string(),
                password  :: string(),
                req_id    :: undefined | ibrowse:req_id()
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
  gen_server:call(Server, Request).

%%% @doc Make a call to a generic server.
%%% If the server is located at another node, that node will be monitored.
%%% If the client is trapping exits and is linked server termination is handled here
%%% @spec call(Server::atom() | pid() | {global, atom()}, Request::term(), Timeout::non_neg_integer()|infinity) -> Response::term()
-spec call(Server::server(), Request::term(), Timeout::non_neg_integer()|infinity) -> Response::term().
call(Server, Request, Timeout) ->
  gen_server:call(Server, Request, Timeout).

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
handle_call(Request, From, State = #state{module = Mod, mod_state = ModState}) ->
  try Mod:handle_call(Request, From, ModState) of
    {ok, Reply, NewModSt} -> {reply, Reply, State#state{mod_state = NewModSt}};
    {stop, Reason, Reply, NewModSt} -> {stop, Reason, Reply, State#state{mod_state = NewModSt}}
  catch
    _:{ok, Reply, NewModSt} -> {reply, Reply, State#state{mod_state = NewModSt}};
    _:{stop, Reason, Reply, NewModSt} -> {stop, Reason, Reply, State#state{mod_state = NewModSt}}    
  end.

%% @hidden
-spec handle_cast({string(), [filter_option() | gen_option() | ibrowse:option()]}, #state{}) -> {noreply, #state{}}.
handle_cast({Method, Options}, State = #state{user = User, password = Password, req_id = OldReqId}) ->
  BasicUrl = ["http://stream.twitter.com/1/statuses/", Method, ".json"],
  {Url, IOptions} = build_url(BasicUrl, Options),
  try ibrowse:send_req(Url, [], get, [], [{basic_auth, {User, Password}},
                                          {stream_to, self()} | IOptions]) of
    {ibrowse_req_id, ReqId} ->
      stream_close(OldReqId),
      {noreply, State#state{req_id = ReqId}};
    {ok, Status, _Headers, Body} ->
      error_logger:error_msg("~p: Error trying to ~s twitter:~n\t~s: ~s~n", [?MODULE, Method, Status, Body]),
      {stop, {error, {Status, Body}}, State};
    {error, Reason} ->
      error_logger:error_msg("~p: Error trying to ~s twitter:~n\t~p~n", [?MODULE, Method, Reason]),
      {stop, {error, Reason}, State}
  catch
    _:{timeout, _} -> %% An ibrowse internal process timed out
      error_logger:error_msg("~p: Internal timeout trying to ~s twitter~n", [?MODULE, Method]),
      {stop, {error, internal_timeout}, State};
    _:Error ->
      error_logger:error_msg("~p: System Error trying to ~s twitter:~n\t~p~n", [?MODULE, Method, Error]),
      {stop, {error, Error}, State}
  end.

%% @hidden
-spec handle_info(term(), state()) -> {noreply, state()} | {stop, term(), state()}.
%%TODO: Catch the ibrowse cases!!
handle_info(Info, State = #state{module = Mod, mod_state = ModState}) ->
  try Mod:handle_info(Info, ModState) of
    {ok, NewModSt} -> {noreply, State#state{mod_state = NewModSt}};
    {stop, Reason, NewModSt} -> {stop, Reason, State#state{mod_state = NewModSt}}
  catch
    _:{ok, NewModSt} -> {noreply, State#state{mod_state = NewModSt}};
    _:{stop, Reason, NewModSt} -> {stop, Reason, State#state{mod_state = NewModSt}}
  end.

%% @hidden
-spec terminate(any(), #state{}) -> any().
terminate(Reason, #state{module = Mod, mod_state = ModState}) ->
  %%TODO: Close the ibrowse connection!!
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

stream_close(OldReqId) ->
  ibrowse:stream_close(OldReqId).