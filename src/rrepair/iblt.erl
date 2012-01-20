% @copyright 2011 Zuse Institute Berlin

%   Licensed under the Apache License, Version 2.0 (the "License");
%   you may not use this file except in compliance with the License.
%   You may obtain a copy of the License at
%
%       http://www.apache.org/licenses/LICENSE-2.0
%
%   Unless required by applicable law or agreed to in writing, software
%   distributed under the License is distributed on an "AS IS" BASIS,
%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%   See the License for the specific language governing permissions and
%   limitations under the License.

%% @author Maik Lange <malange@informatik.hu-berlin.de>
%% @doc    Invertible Bloom Lookup Table
%%         Operations: Insert, Delete, Get, ListEntries
%% @end
%% @reference 
%%          1) M. T. Goodrich, M. Mitzenmacher
%%          <em>Invertible Bloom Lookup Tables</em> 
%%          2011 ArXiv e-prints. 1101.2245
%%          2) D.Eppstein, M.T.Goodrich, F.Uyeda, G.Varghese
%%          <em>Whats the Difference? Efficient Set Reconciliation without Prior Context</em>
%%          2011 SIGCOMM'11 Vol.41(4)
%% @version $Id$

-module(iblt).

-include("record_helpers.hrl").
-include("scalaris.hrl").

-export([new/2, new/3, insert/3, delete/3, get/2, list_entries/1]).
-export([is_element/2]).
-export([get_fpr/1, get_prop/2]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Types
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-define(Check_sum_fun(X), erlang:crc32(integer_to_list(X))). %hash function for checksum building

-type key()     :: integer().
-type value()   :: integer().
-type cell()    :: {Count       :: non_neg_integer(),
                    KeySum      :: key(),
                    KeyHashSum  :: integer(),   %sum c(x) of all inserted keys x, for c = any hashfunction not in hfs
                    ValSum      :: value(),
                    ValHashSum  :: integer()}.  %sum c(y) of all inserted values y, for c = any hashfunction not in hfs

-type table() :: [] | [{ColNr :: pos_integer(), Cells :: [cell()]}].

-record(iblt, {
               hfs        = ?required(iblt, hfs) :: ?REP_HFS:hfs(),    %HashFunctionSet
               table      = []                   :: table(),
               cell_count = 0                    :: non_neg_integer(), 
               col_size   = 0                    :: non_neg_integer(), %cells per column
               item_count = 0                    :: non_neg_integer()  %number of inserted items
               }).

-opaque iblt() :: #iblt{}. 

-type option()  :: prime.
-type options() :: [] | [option()].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% API
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec new(?REP_HFS:hfs(), pos_integer()) -> iblt().
new(Hfs, CellCount) ->
    new(Hfs, CellCount, [prime]).

-spec new(?REP_HFS:hfs(), pos_integer(), options()) -> iblt().
new(Hfs, CellCount, Options) ->
    K = ?REP_HFS:size(Hfs),
    {Cells, ColSize} = case proplists:get_bool(prime, Options) of
                            true ->
                                CCS = prime:get_nearest(erlang:round(CellCount / K)),
                                {CCS * K, CCS};
                            false ->
                                RCC = resize(CellCount, K),
                                {RCC, erlang:round(RCC / K)}
                        end,
    SubTable = [{0, 0 ,0, 0, 0} || _ <- lists:seq(1, ColSize)],
    Table = [ {I, SubTable} || I <- lists:seq(1, K)],
    #iblt{
          hfs = Hfs, 
          table = Table, 
          cell_count = Cells, 
          col_size = ColSize,
          item_count = 0
          }.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec insert(iblt(), key(), value()) -> iblt().
insert(IBLT, Key, Value) ->
    change_table(IBLT, add, Key, Value).

-spec delete(iblt(), key(), value()) -> iblt().
delete(IBLT, Key, Value) ->
    change_table(IBLT, remove, Key, Value).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec change_table(iblt(), add | remove, key(), value()) -> iblt().
change_table(#iblt{ hfs = Hfs, table = T, item_count = ItemCount, col_size = ColSize } = IBLT, 
             Operation, Key, Value) ->
    %TODO calculate each column in a separate process
    NT = lists:foldl(
           fun({ColNr, Col}, NewT) ->
                   NCol = change_cell(Col, 
                                      ?REP_HFS:apply_val(Hfs, ColNr, Key) rem ColSize,
                                      Key, Value, Operation),
                   [{ColNr, NCol} | NewT]
           end, [], T),
    IBLT#iblt{ table = NT, item_count = ItemCount + case Operation of
                                                        add -> 1;
                                                        remove -> -1
                                                    end}.   

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec change_cell([cell()], pos_integer(), key(), value(), add | remove) -> [cell()].
change_cell(Column, CellNr, Key, Value, Operation) ->        
    {HeadL, [Cell | TailL]} = lists:split(CellNr, Column),
    {Count, KeySum, KHSum, ValSum, VHSum} = Cell,
    KeyCheck = ?Check_sum_fun(Key),
    ValCheck = ?Check_sum_fun(Value),
    R = case Operation of
        add -> lists:flatten([HeadL, 
                              {Count + 1, 
                               KeySum + Key, KHSum + KeyCheck,
                               ValSum + Value, VHSum + ValCheck}, 
                              TailL]);
        remove when Count > 0 -> lists:flatten([HeadL, 
                                                {Count - 1, 
                                                 KeySum - Key, KHSum - KeyCheck,
                                                 ValSum - Value, VHSum - ValCheck}, 
                                                TailL]);
        remove when Count =:= 0 -> Column
    end,
    %ct:pal("ChangeCell Pos=~p ; Key=~p ; OLD Col=~w~nNEW Col=~p", 
    %       [CellNr, Key, Column, R]),
    R.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec get(iblt(), key()) -> value() | not_found.
get(#iblt{ table = T } = IBLT, Key) ->
    p_get(T, IBLT, Key).

-spec p_get(Table, IBLT, Key) -> Result when
    is_subtype(Table,     table()),
    is_subtype(IBLT,      iblt()),
    is_subtype(Key,       key()),
    is_subtype(Result,    value() | not_found).
p_get([], _, _) -> not_found;
p_get([{ColNr, Col} | T], #iblt{ hfs = Hfs, col_size = ColSize} = IBLT, Key) ->
    {Count, KeySum, KHSum, ValSum, VHSum} = 
        lists:nth((?REP_HFS:apply_val(Hfs, ColNr, Key) rem ColSize) + 1, Col),
    case Count =:= 1 
             andalso KeySum =:= Key 
             andalso KHSum =:= ?Check_sum_fun(Key)
             andalso VHSum =:= ?Check_sum_fun(ValSum) of
        true -> ValSum;
        false -> p_get(T, IBLT, Key)
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% @doc lists all correct entries of this structure
%     correct entries can be retrieved out of pure cells
%     a pure cell := count = 1 and check_sum(keySum)=keyHashSum and check_sum(valSum)=valHashSum
-spec list_entries(iblt()) -> [{key(), value()}].
list_entries(IBLT) ->
    p_list_entries(IBLT, []).

-spec p_list_entries(iblt(), [{key(), value()}]) -> [{key(), value()}].
p_list_entries(#iblt{ table = T } = IBLT, Acc) ->
    case get_any_entry(T, []) of
        [] -> Acc;
        L ->
            NewIBLT = lists:foldl(fun({Key, Val}, NT) -> 
                                          delete(NT, Key, Val) 
                                  end, IBLT, L),
            p_list_entries(NewIBLT, lists:append([L, Acc]))
    end.

% tries to find any pure entry 
-spec get_any_entry(table(), [{key(), value()}]) -> [{key() | value()}].
get_any_entry([], Acc) -> 
    Acc;
get_any_entry([{_, Col} | T], Acc) ->
    Result = [{Key, Val} || {Count, Key, KCheck, Val, VCheck} <- Col, 
                            Count =:= 1,
                            ?Check_sum_fun(Key) =:= KCheck,
                            ?Check_sum_fun(Val) =:= VCheck],
    if 
        Result =:= [] -> get_any_entry(T, lists:append([Result, Acc]));
        true -> Result
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec is_element(iblt(), key()) -> boolean().
is_element(#iblt{ hfs = Hfs, table = T, col_size = ColSize }, Key) ->
    Found = lists:foldl(
              fun({ColNr, Col}, Count) ->
                      {C, _, _, _, _} = lists:nth((?REP_HFS:apply_val(Hfs, ColNr, Key) rem ColSize) + 1, Col),
                      Count + if C > 0 -> 1; 
                                 true -> 0 end
                      end, 0, T),
    Found =:= ?REP_HFS:size(Hfs).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% @doc calculates actual false positive rate depending on saturation degree
-spec get_fpr(iblt()) -> float().
get_fpr(#iblt{  hfs = Hfs, cell_count = M, item_count = N }) ->
    K = ?REP_HFS:size(Hfs),
    math:pow(1 - math:pow(math:exp(1), (-K*N)/M), K).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec get_prop(atom(), iblt()) -> any().
get_prop(Prop, IBLT) ->
    case Prop of
        item_count -> IBLT#iblt.item_count;
        col_size -> IBLT#iblt.col_size;
        cell_count -> IBLT#iblt.cell_count
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% helpers
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% @doc Increases Val until Val rem Div == 0.
-spec resize(pos_integer(), pos_integer()) -> pos_integer().
resize(Val, Div) when Val rem Div == 0 -> 
    Val;
resize(Val, Div) when Val rem Div /= 0 -> 
    resize(Val + 1, Div).
