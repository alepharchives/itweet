%%%-------------------------------------------------------------------
%%% @author Fernando Benavides <fernando.benavides@inakanetworks.com>
%%% @copyright (C) 2011 Inaka Labs SRL
%%% @doc Tests for itweep module
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

-module(itweep_tests).

-behaviour(itweep).

-record(state, {}).

-export([start/2, stop/1]).
-export([handle_call/3, handle_event/3, handle_info/2, handle_status/2, init/1, terminate/2]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% API FUNCTIONS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec start(User::string(), Password::string()) -> itweep:start_result().
start(User, Password) ->
  itweep:start(?MODULE, [], [{user, User}, {password, Password}]).

-spec stop(Pid::pid()) -> ok.
stop(Pid) ->
  itweep:call(Pid, stop).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% ITWEEP FUNCTIONS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @hidden
-spec init(Args::term()) -> itweep:init_result().
init([]) ->
  {ok, #state{}}.

%% @hidden
-spec handle_status(Status::itweep:json_object(), State::term()) -> itweep:handler_result().
handle_status(Status, State) ->
  io:format("~p:~p -> Status: ~p~n", [?MODULE, ?LINE, Status]),
  {ok, State}.

%% @hidden
-spec handle_event(Event::atom(), Data::itweep:json_object(), State::term()) -> itweep:handler_result().
handle_event(Event, Data, State) ->
  io:format("~p:~p -> ~p: ~p~n", [?MODULE, ?LINE, Event, Data]),
  {ok, State}.

%% @hidden
-spec handle_call(Msg::term(), From::reference(), State::term()) -> itweep:call_result().
handle_call(stop, _From, State) ->
  io:format("~p:~p stopping~n", [?MODULE, ?LINE]),
  {stop, normal, ok, State}.

%% @hidden
-spec handle_info(Msg::term(), State::term()) -> itweep:handler_result().
handle_info(Msg, State) ->
  io:format("~p:~p -> info:~n\t~p~n", [?MODULE, ?LINE, Msg]),
  {ok, State}.

%% @hidden
-spec terminate(Reason :: normal | shutdown | term(), State::term()) -> _.
terminate(Reason, _State) ->
  io:format("~p:~p terminating: ~p~n", [?MODULE, ?LINE, Reason]),
  ok.