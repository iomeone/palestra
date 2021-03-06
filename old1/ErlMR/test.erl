-module(test).
-export([start/1,
         wc/1,
         m3gzc/1,
         m3gzc2/1]).
-import(mrlib,
        [mapreduce/3,
         info/2]).

% simple test %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
simple_map({K, V}, Emit) ->
    Emit({K, V}),
    Emit({K, V * V}).

simple_reduce({K, ListOfV}) ->
    {K, lists:sum(ListOfV)}.

start(N) ->
    TestInput = [{a, 1},
                 {b, 2},
                 {c, 3}],
    Map = fun simple_map/2,
    Reduce = fun simple_reduce/1,
    mapreduce(
      N,
      TestInput,
      [{map, Map}, {reduce, Reduce}]).

% word count %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
wc_load_file(Filename) ->
    {ok, S} = file:open(Filename, read),
    wc_load_file_acc([], 1, S).

wc_load_file_acc(Acc, Lineno, S) ->
    case io:get_line(S, '') of
        eof -> file:close(S), lists:reverse(Acc);
        Line -> wc_load_file_acc([{Lineno, Line}|Acc], Lineno + 1, S)
    end.

wc_map({_, Line}, Emit) ->
    lists:foreach(
      fun(Char) -> Emit({[Char], 1}) end,
      Line).

wc_reduce({K, Vals}) -> {K, lists:sum(Vals)}.

wc(N) ->
    InputList = wc_load_file("mrlib.erl"),
    Map = fun wc_map/2,
    Reduce = fun wc_reduce/1,
    Output = mapreduce(
               N,
               InputList,
               [{map, Map}, {reduce, Reduce}]),
    lists:reverse(lists:keysort(2, Output)).

% simple m3gzc %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%mk_datum_input_format(Filename) ->
%    {ok, S} = file:open(Filename, read),
%    mk_datum_input_format_from_file(1, S).
%
%mk_datum_input_format_from_file(Lineno, S) ->
%    fun () ->
%            case io:read(S, '') of
%                {ok, Datum} -> {{Lineno, Datum},
%                                mk_datum_input_format_from_file(Lineno + 1, S)};
%                eof -> file:close(S), eof
%            end
%    end.

m3_loadfile(Filename) ->
    {ok, S} = file:open(Filename, read),
    {ok, Data} = io:read(S, ''),
    file:close(S),
    Data.

m3_mk_pair(A1, A2) ->
    m3_mk_pair_acc([], 0, 0, A1, A2, array:size(A1), array:size(A2)).

% Index, Array, Size
m3_mk_pair_acc(Acc, I1, I2, A1, A2, S1, S2) ->
    if
        I2 == S2 -> lists:reverse(Acc);
        true -> NextI1 = I1 + 1,
                Pair = {{I1, I2}, {array:get(I1, A1), array:get(I2, A2)}},
                NewAcc = [Pair|Acc],
                if
                    NextI1 == S1 ->
                        m3_mk_pair_acc(NewAcc,
                                       0, I2 + 1,
                                       A1, A2, S1, S2);
                    true ->
                        m3_mk_pair_acc(NewAcc,
                                       NextI1, I2,
                                       A1, A2, S1, S2)
                end
    end.

dotproduct(V1, V2) -> dotproduct_acc(0, V1, V2).

dotproduct_acc(Acc, [], _) -> Acc;
dotproduct_acc(Acc, _, []) -> Acc;
dotproduct_acc(Acc, [A1|V1], [A2|V2]) ->
    {D1, X1} = A1,
    {D2, X2} = A2,
    if
        D1 > D2 -> dotproduct_acc(Acc, [A1|V1], V2);
        D2 < D1 -> dotproduct_acc(Acc, V1, [A2|V2]);
        true -> dotproduct_acc(Acc + X1 * X2, V1, V2)
    end.

squarelength(V) -> dotproduct(V, V).

% gzc = exp(-(|Vp-Vx|/|Vp-Vn|/lam)^2) - exp(-(|Vn-Vx|/|Vp-Vn|/lam)^2)
% |Vp-Vx|^2 = |Vp|^2 + |Vx|^2 - 2 * dot(Vp, Vx)
% |Vn-Vx|^2 = |Vn|^2 + |Vx|^2 - 2 * dot(Vn, Vx)
% |Vp-Vn|^2 = |Vp|^2 + |Vn|^2 - 2 * dot(Vp, Vn)
gzc(Lambda, Vp, Vn, Vx) ->
    SLVp = squarelength(Vp),
    SLVn = squarelength(Vn),
    SLVx = squarelength(Vx),
    VpVx = dotproduct(Vp, Vx),
    VnVx = dotproduct(Vn, Vx),
    VpVn = dotproduct(Vp, Vn),
    VpVx2 = SLVp + SLVx - 2 * VpVx,
    VnVx2 = SLVn + SLVx - 2 * VnVx,
    VpVn2 = SLVp + SLVn - 2 * VpVn,
    Sigma = Lambda * Lambda * VpVn2,
    math:exp(-VpVx2 / Sigma) - math:exp(-VnVx2 / Sigma).

m3_gzc_mk_map(Lambda, Tests) ->
    fun ({{PosIdx, _}, {PosVec, NegVec}}, Emit) ->
            lists:foreach(
              fun ({IdxLabel, Vx}) ->
                      Score = gzc(Lambda, PosVec, NegVec, Vx),
                      Emit({{IdxLabel, PosIdx}, Score})
              end,
              Tests)
    end.

m3_gzc_min_reduce({{IdxLabel, _}, ListOfScore}) -> {IdxLabel, lists:min(ListOfScore)}.

m3_gzc_max_reduce({IdxLabel, ListOfScore}) -> {IdxLabel, lists:max(ListOfScore)}.

% TestData starts from 1
extidx(Data) ->
    Len = length(Data),
    lists:map(fun ({Idx, {Label, Vx}}) -> {{Idx, Label}, Vx} end,
              lists:zip(lists:seq(1, Len),
                        Data)).

m3gzc(N) ->
    info("go~~", []),
    TrainDataPath = "testdata/traindata.erldat",
    TestDataPath = "testdata/testdata.erldat",
    info("load files: ~p, ~p", [TrainDataPath, TestDataPath]),
    TrainData = m3_loadfile(TrainDataPath),
    TestData = m3_loadfile(TestDataPath),
    info("#train=~p, #test=~p", [length(TrainData), length(TestData)]),
    info("preprocess", []),
    {PosDataLWithLabel, NegDataLWithLabel} =
        lists:partition(
          fun({Label, _}) -> Label > 0 end,
          TrainData),
    RemoveLabel = fun (L) -> lists:map(fun ({_, V}) -> V end, L) end,
    PosDataL = RemoveLabel(PosDataLWithLabel),
    NegDataL = RemoveLabel(NegDataLWithLabel),
    PosData = array:from_list(PosDataL),
    NegData = array:from_list(NegDataL),
    info("mkpair", []),
    InputList = m3_mk_pair(PosData, NegData),
    Lambda = 0.5,
    info("start mapreduce", []),
    Output = mapreduce(
               N,
               InputList,
               [{map, m3_gzc_mk_map(Lambda, extidx(TestData))},
                {reduce, fun m3_gzc_min_reduce/1},
                {reduce, fun m3_gzc_max_reduce/1}]),
    lists:map(
      fun ({{Idx, Label}, Value}) ->
              {Idx, Label * Value > 0, Value}
      end,
      lists:keysort(1, Output)).

% m3gzc2: another version of mapreduce m3gzc %%%%%%%%%%%%%%%
m3gzc2_mk_map(Lambda, NegData, Tests) ->
    fun ({_, Vp}, Emit) ->
            lists:foreach(
              fun ({IdxLabel, Vx}) ->
                      Score = lists:min(
                                lists:map(
                                  fun (Vn) ->
                                          gzc(Lambda, Vp, Vn, Vx)
                                  end,
                                  NegData)),
                      Emit({IdxLabel, Score})
              end,
              Tests)
    end.

m3gzc2_reduce(KV) -> m3_gzc_max_reduce(KV).

m3gzc2(N) ->
    info("go~~", []),
    TrainDataPath = "testdata/traindata.erldat",
    TestDataPath = "testdata/testdata.erldat",
    info("load files: ~p, ~p", [TrainDataPath, TestDataPath]),
    TrainData = m3_loadfile(TrainDataPath),
    TestData = m3_loadfile(TestDataPath),
    info("#train=~p, #test=~p", [length(TrainData), length(TestData)]),
    info("preprocess", []),
    {PosDataLWithLabel, NegDataLWithLabel} =
        lists:partition(
          fun({Label, _}) -> Label > 0 end,
          TrainData),
    RemoveLabel = fun (L) -> lists:map(fun ({_, V}) -> V end, L) end,
    PosData = RemoveLabel(PosDataLWithLabel),
    NegData = RemoveLabel(NegDataLWithLabel),
    InputList = lists:zip(lists:seq(1, length(PosData)), PosData),
    Lambda = 0.5,
    info("start mapreduce", []),
    Output = mapreduce(
               N,
               InputList,
               [{map, m3gzc2_mk_map(Lambda,
                                    NegData,
                                    extidx(TestData))},
                {reduce, fun m3gzc2_reduce/1}]),
    lists:map(
      fun ({{Idx, Label}, Value}) ->
              {Idx, Label * Value > 0, Value}
      end,
      lists:keysort(1, Output)).
