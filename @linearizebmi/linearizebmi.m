function [LMI,LMIstr,gBMI,BMI] = linearizebmi(S, vlist, v0list, G)
% BMIの文字列を受け取り，逐次LMIの値を返すパーサー
%   
%   OUTPUT:
%       LMI: 逐次LMI(変換後)の値
%       LMIstr: 拡大LMIの文字列
%       BMI: BMI(変換前)の値
%       gBMI: 一般化BMI(He(Q+LXNYR))の行列の情報(構造体)
%
%   INPUT:
%       S: BMIの文字列
%           ex) "P*A+P*B*K*C+A'*P'+C'*K'*B'*P'"
%       vlist: 決定変数の文字列
%           ex) {'P','K'}
%       v0list: 暫定解の文字列
%           ex) {'P0','K0'}
%       G: gammaの定数倍，デフォルトで単位行列
%
%
%   ※ワークスペースの変数の値を利用して計算するので，
%     linearizebmi関数を呼び出す前に，
%     あらかじめに変数を宣言する必要がある．
%       ex) 
%           X = sdpvar(2,2)
%           Y = sdpvar(3,2)
%           A = rand(2,3)
%           X0= rand(2,2) 
%           Y0= rand(3,2)
%           LMI = linearizebmi("X*A*Y+(X*A*Y)'",{'X','Y'},{'X0','Y0'})
%
%
%   現段階：
%       ・()を使った分配法則や転置が可能
%       ・数値を直接記述した場合のスカラー倍にまだ対応できていない, 変数名は可能
%       ・行列[]の和による記述が可能
%       ・ベクトル同士の積による行列の記述が可能
%

% this value should be passed by options
t=0.99;


% 文字列を文字ベクトルに変換
if isa(S,'string')
    S = char(S);
end
% str2sym(S)

% 関数引数の取得(char)
if length(vlist) ~= length(v0list)
    error('The argument 2 and 3 (as list) must be the same lengths')
end

try
    Xstr =char(vlist{1});
    Ystr =char(vlist{2});
    X0str=char(v0list{1});
    Y0str=char(v0list{2});
catch 
    error('varargin{2}, varargin{3} must be the char list');
end


Zstr = '';
Z0str = '';
if length(vlist) == 3
    % 分割行列も決定変数のとき
    Zstr =char(vlist{3});
    Z0str=char(v0list{3});
end
% Zの存在チェックflag
isZ = ~isempty(Zstr);


% 決定変数の取得
try
    % 呼び出し関数内の値を入手
    X = evalin('caller', Xstr);
    Y = evalin('caller', Ystr);
catch
    % 実行スクリプト内の値を入手
    X = evalin('base', Xstr);
    Y = evalin('base', Ystr);
end

% X,Yが決定変数(sdpvar)かどうかチェック
if ~isa(X,'sdpvar')
    error("'%s' must be the 'sdpvar' class",Xstr);
elseif ~isa(Y,'sdpvar')
    error("'%s' must be the 'sdpvar' class",Ystr);
end

    
% 暫定解の取得
try
    % 呼び出し関数内の値を入手
    X0 = evalin('caller', X0str);
    Y0 = evalin('caller', Y0str);
catch
    % 実行スクリプト内の値を入手
    X0 = evalin('base', X0str);
    Y0 = evalin('base', Y0str);
end

% Zも同様に決定変数と暫定解を取得
if isZ
    try
        Z = evalin('caller', Zstr);
        Z0 = evalin('caller', Z0str);
    catch
        Z = evalin('base', Zstr);
        Z0 = evalin('base', Z0str);
    end
end


% 決定変数と暫定解のサイズチェック
if ~isequal(size(X),size(X0))
    error("size of '%s' and '%s' must be the same",Xstr,X0str);
end
if ~isequal(size(Y),size(Y0))
    error("size of '%s' and '%s' must be the same",Ystr,Y0str);
end
if isZ && ~isequal(size(Z),size(Z0))
    error("size of '%s' and '%s' must be the same",Zstr,Z0str);
end

% Gの取得
if nargin<4
    % デフォルト：単位行列
    Gchar = [func2str(@eye) '(' num2str(size(Y,1)) ')'];
    G = eye(size(Y,1));
elseif isa(G,'string') || isa(G,'char') 
    % G のclassチェック
    Gchar = string(G);
    G = evalin('base',G);
else
    error('varargin{4} must be "char" class')
end



%% 入力の構文エラーチェック
try
    % bmiのstrのままevalinで実行することで
    % yalmip本体のエラー処理に任せる
    testBMI = evalin('base',S);
catch ME
    rethrow(ME)
end



%%% 極配置でYのエラーチェックが通らない
%%% 構造を持ったsdpvarのreplaceがうまくいかない
% testBMI
% Y
% Y0
% zeros(size(Y))
% replace(testBMI,X,X0)
% replace(testBMI,Y,Y0)
% isequal(replace(testBMI,Y,zeros(size(Y))),zeros(size(testBMI)))
% is(replace(testBMI,X,zeros(size(X))),'linear')

% X,Yが記述制約のmember(sdpvar)かどうか調べる
% if isequal(replace(testBMI,X,zeros(size(X))),zeros(size(testBMI))) ||...
%    is(replace(testBMI,X,zeros(size(X))),'linear') 
% else
%     error("'%s' is not a member in this constraint.",Xstr);
% end
% if isequal(replace(testBMI,Y,zeros(size(Y))),zeros(size(testBMI))) ||...
%    is(replace(testBMI,Y,zeros(size(Y))),'linear') 
% else
%     error("'%s' is not a member in this constraint.",Ystr);
% end

%% 字句解析の前処理(pre-process)

% 正規表現用変数の初期化
% regdeclare関数内で定義された変数の使用例
% ex)
%   global TERM
%   term = regexp(S,TERM,'match');
regdeclare();

% ,を空文字に変換
global FUNC_OR_VAR
% S = char(regexprep(S,'(?<!\(\w+),',' '));
S = char(regexprep(S,"(?<!\(("+FUNC_OR_VAR+"(,*))+),",' '));

% 空文字を削減
S = char(regexprep(S,'(\s+)',' '));

% []の入れ子をなくす
% S(1),S(end)
if S(1) == "[" && S(end) == "]"...
%          && S(2) == "[" && S(end-1) == "]"
    S = S(2:end-1);
end
% S


% ベクトルの積
global VEC_PROD_VEC
while regexp(S,VEC_PROD_VEC)
    S = prodvec(S);
end
% S

% 行列の転置
global MAT_TRANSPOSE
while regexp(S,MAT_TRANSPOSE)
    S = transposematrix(S);
end
% S

% 括弧の処理
% eye(2,2)のように，関数の括弧は処理しない
global BRACKET_POLY % (?<!\w+)\((.*)\)
while regexp(S,BRACKET_POLY)
    % 括弧()を展開する
    S = divbracket(S);
end
% S

% 転置'の処理
% 奇数個:1コ に変換
S = regexprep(S,"\'(\'\')*","\'");
% 偶数個:0コ に変換
S = regexprep(S,"(\'\')+","");
%
% S


%% 字句解析
% ex) "P*A+P*B*K*C"
% =>  {{"P","B"},{"P","B","K","C"}}
% ex) "P'*A'"
% =>  {{"P'","A'"}}

termlist = {}; % 項のリスト
varlist = {};  % 変数定数の配列(一時的)
varstr = "";   % 1つの変数の文字列(一時的)

% 制約が行列の場合
columlist = {}; % 行のリスト，termlistをこの中に入れる
colnum = 1;     % 行数
rownum = 1;     % 列数

% 複数行列の和に対応
matrixlist = {}; % 行列[...]の字句解析結果(smatrix)を格納する, 最終的に1つのsmatrixにする

% 変数名(関数名)のマッチング
global FUNC_OR_VAR
i = 0;

% デバッグ用:
% disp("==========")
% 入力文字列を1文字ずつ解析
% for i=1:strlength(S)
while i < strlength(S)
    i = i+1;
    % デバッグ用:
    % disp("-----")
    % disp(colnum+" "+rownum)
    % i,S(i),varstr,termlist

    
    % 変数の文字列の場合
    % ex) 'var' = 'v'+'a'+'r' 
    % 正規表現[a-zA-Z_0-9], (), '
    % ex) a0は変数だが，0aは変数でない -> どう処理する？
    if regexp(S(i), "[\w\(\,\)\']")
        % どこまでが変数名かを推定する
        % 変数名の更新
        % varstr = varstr + S(i);
        [varstr,startidx,endidx] = regexp(S(i:end),FUNC_OR_VAR,'match','once');
        varstr = string(varstr);
        i = i + endidx - 1; % update while loop index
        if i == strlength(S) 
            % 終端文字の場合，varlistをtermlistに追加
            % "A]"とかだと別処理が必要，"[...]"の処理
            [varlist, varstr] = updateList(varlist,varstr);
            [termlist, varlist] = updateList(termlist,varlist,1);
            [columlist, termlist] = updateList(columlist,termlist);
            %
            % smatrixをmatrixlistに追加
            if colnum > 1 || rownum > 1
                % ブロック行列の場合
                smatrix = reshape(columlist,colnum,rownum).';
            else
                % そうでない場合
                smatrix = columlist;
            end
            [matrixlist,smatrix] = updateList(matrixlist,smatrix);
        end
        continue
    end
    
    % 演算子の場合
    % 和+
    if regexp(S(i), '\+')
        if varstr == ""
            continue
        end
        % varstrをvarlistに追加, varstr初期化
        [varlist, varstr] = updateList(varlist,varstr);
        % varlistをtermlistに追加，varlist初期化
        [termlist, varlist] = updateList(termlist,varlist,1);
        continue
    end
    % 積*
    if regexp(S(i), '\*')    
        [varlist, varstr] = updateList(varlist,varstr);
        continue
    end
    
    % 差-
    % ex) "-A*B": {"-","A","B"}
    if regexp(S(i), '\-')
        % 前までの項をリスト追加(あれば)
        if varstr ~= ""
            [varlist, varstr] = updateList(varlist,varstr);
            [termlist, varlist] = updateList(termlist,varlist,1);
        end
        % 新しい項の1文字目に入れる
        varstr = varstr + S(i);
        [varlist, varstr] = updateList(varlist,varstr);
        continue
    end
    
    % シングルクオーテーションの場合
    % ex) A'*B'：行列の転置をする時に使う
    % 現状 \w と同じ処理
%     if regexp(S(i), "\'")
%         varstr = varstr + S(i);
%         if i == strlength(S) 
%             % 終端文字の場合，termstrをtermlistに追加
%             [varlist, varstr] = updateList(varlist,varstr);
%             [termlist, varlist] = updateList(termlist,varlist,1);
%             [columlist, termlist] = updateList(columlist,termlist);
%         end
%         continue
%     end
        
    % 空文字の場合
    % ex) '[A B]' : 行列の列を生成するときに使う
    if regexp(S(i), '\s')    
        if ~isempty(regexp(S(i-1), '\s', 'once')) ||...
           ~isempty(regexp(S(i), '[\*\+]', 'once'))   
            continue
        elseif regexp(S(i-1), "[\w\'\)]")
            [varlist, varstr] = updateList(varlist,varstr);
            [termlist, varlist] = updateList(termlist,varlist,1);
            [columlist, termlist] = updateList(columlist,termlist);
            % 列数の更新
            rownum = rownum + 1;
            continue
        end
    end
    % セミコロン;の場合
    % ex) '[A;B]' : 行列の行を生成するときに使う
    if regexp(S(i), ';')
        [varlist, varstr] = updateList(varlist,varstr);
        [termlist, varlist] = updateList(termlist,varlist,1);
        [columlist, termlist] = updateList(columlist,termlist);
        % 行数更新
        colnum = colnum + 1;
        rownum = 1;
        continue
    end
    
    % [の場合
    % 制約は行列
    if regexp(S(i), '\[')
        % disp("Helo")
        % 行列を解析するための初期化
        termlist = {}; % 項のリスト
        varlist = {};  % 変数定数の配列(一時的)
        varstr = "";   % 1つの変数の文字列(一時的)
        columlist = {}; % 行のリスト
        colnum = 1;     % 行数
        rownum = 1;     % 列数
        continue
    end
    % ]の場合
    % 行列おわり
    if regexp(S(i), '\]')
        % disp("bye")
        [varlist, varstr] = updateList(varlist,varstr);
        [termlist, varlist] = updateList(termlist,varlist,1);
        [columlist, termlist] = updateList(columlist,termlist);
        %
        % smatrixの生成
        % Sの最終形態(cellの行列), columlistを縦に並べたもの
        if colnum > 1 || rownum > 1
            % ブロック行列の場合
            smatrix = reshape(columlist,colnum,rownum).';
        else
            % そうでない場合
            smatrix = columlist;
        end
        % smatrixをmatrixlistに追加
        [matrixlist,smatrix] = updateList(matrixlist,smatrix);
        
        % 行列を解析するための初期化
%         termlist = {}; % 項のリスト
%         varlist = {};  % 変数定数の配列(一時的)
%         varstr = "";   % 1つの変数の文字列(一時的)
        columlist = {}; % 行のリスト
        colnum = 1;     % 行数
        rownum = 1;     % 列数
        
        continue
    end
    
end

% デバッグ
% columlist
% colnum, rownum
% smatrix
% matrixlist



%% 行列(matrixlist)の結合

[scol,srow] = cellfun(@size,matrixlist);

matlist = {};       % matrixlistでsizeが最大の行列(複数)，この中に双線形項が必ずある
othermatlist = {};  % othermatlist: smatrixよりsizeが小さい行列，関数blkdiagなど，必ず線形項

% matlistとothermatlistの分離
for i=1:length(matrixlist)
    mat = matrixlist{1,i};
    if isequal(size(mat),[max(scol) max(srow)])
        matlist = updateList(matlist,mat);
    else
        othermatlist = cat(2,othermatlist,mat);
    end
end

% matlist
% othermatlist

% matlistのみの計算
for i=1:length(matlist)
    mat = matlist{1,i};
    if i == 1
        smatrix = mat;
        continue
    end 
    % 各smatrixの項を結合する
    for col=1:size(mat,1)
        for row=1:size(mat,2)
            smatrix{col,row} = cat(1,smatrix{col,row},mat{col,row});
        end 
    end
end

% デバッグ用:
% smatrix
% [a,b] = cellfun(@cellfuntest,smatrix)


%% 項のマイナス(-)符号を削減
% 奇数個: (-X)*(-Y)*(-Z) => -X*Y*Z
% 偶数個: (-X)*(-Y)*Z    => X*Y*Z

smatrix = cellfun(@rmngsign,smatrix,'UniformOutput',false);


%% sdpvarの変数名の取得

% 一時的リスト
sdpvarnamelist = []; % sdpvarの変数名list

% すべての変数名を調べて，evalinでsdpvarだったら変数名を記録
for col=1:size(smatrix,1)
    % 各行ベクトル
    for row=1:size(smatrix,2)
        % 各行列要素
        % disp(col+" "+row)
        termlist = smatrix{col,row};
        for i=1:size(termlist,1)
            % 要素の各項
            term = termlist{i,1};
            for j=1:size(term,2)
                % 項のそれぞれの変数
                var = term{1,j};
                % 転置ははずす
                if regexp(var, "\'")
                    var = regexprep(var,"\'","");
                end
                % classがsdpvarなら変数名を記録
                try
                    data = evalin('base',var);
                    if isequal(class(data),'sdpvar')
                        %
                        % use var in function args
                        if regexp(var, "\(.*\)")
                            var = regexprep(var, "\w*\(","");
                            var = regexprep(var, "\)","");
                        end
                        sdpvarnamelist = [sdpvarnamelist, var];
                    end
                catch
                    continue
                end
            end
        end
    end
end


% sdpvarnamelist
% unique(sdpvarnamelist,'stable')

% オプションとしてsdpvar変数名を出力
gBMI.sdpvarname = unique(sdpvarnamelist,'stable');


%% そもそもLMIならそのまま出力

% testBMI
gBMI.isbmi = true;
if is(testBMI,'linear')
    LMI = testBMI;
    LMIstr = "";
    BMI = NaN;
    gBMI.isbmi = false;
    % disp("This is LMI")
    return
end



%% 線形項と双線形項の分離
% 行列
linearmatrix = smatrix; % 定数項，1次項
binearmatrix = smatrix; % 双線形項

% 一時的リスト
linearlist = {}; % 定数項，1次項
binearlist = {}; % 双線形項


for col=1:size(smatrix,1)
    % 各行ベクトル
    for row=1:size(smatrix,2)
        % 各行列要素
        % disp(col+" "+row)
        termlist = smatrix{col,row};
        for i=1:size(termlist,1)
            % 要素の各項
            term = termlist{i,1};
            %
            varcount = 0; % 決定変数の数
            for j=1:size(term,2)
                % 項のそれぞれの変数
                var = term{1,j};
%                 if ~isempty(regexp(var, Xstr, 'once')) ||...
%                    ~isempty(regexp(var, Ystr, 'once'))
%                     varcount = varcount + 1;
%                 end
                % sdpvarかどうか調べる
                try
                    data = evalin('base',var);
                catch
                    continue
                end
                if isequal(class(data),'sdpvar')
                    varcount = varcount + 1;
                end
                
                if varcount >= 2
                    binearlist = updateList(binearlist,term,1);
                    break
                elseif j == size(term,2)
                    linearlist = updateList(linearlist,term,1);
                    break
                end
            end
        end
        % 線形項の行列
        linearmatrix(col,row) = {linearlist};
        linearlist = {};
        % 双線形項の行列
        binearmatrix(col,row) = {binearlist};
        binearlist = {};
    end
end
% デバッグ用:
% linearmatrix
% binearmatrix


%% 双線形項のheの分離

orgmatrix = binearmatrix; % 転置なし行列
hematrix = binearmatrix;  % 転置あり行列

orgtermlist = {};    % 項のリスト(初期化)
hetermlist = {};     % 項の転置ありリスト(初期化)

% 項に'があったら，hematrixに追加
for col=1:size(binearmatrix,1)
    % 各行ベクトル
    for row=1:size(binearmatrix,2)
        % 各行列要素
        % disp(col+" "+row)
        termlist = binearmatrix{col,row};
        for i=1:size(termlist,1)
            % 要素の各項
            term = termlist{i,1};
            for j=1:size(term,2)
                % 項のそれぞれの変数
                var = term{1,j};
                if regexp(var, "\'")
                    % var
                    % hetermlist: 転置あり
                    hetermlist = updateList(hetermlist,term,1);
                    break
                else
                    % termlist: 転置なし
                    % if col == row && col >= 2
                    %     % (2,2),(3,3)要素は1/2倍する
                    %     % スカラー倍を実装しないとできない
                    % end
                    orgtermlist = updateList(orgtermlist,term,1);
                    break
                end
            end
        end
        % 転置なし行列の更新
        orgmatrix(col,row) = {orgtermlist};
        orgtermlist = {};
        % 転置あり行列の更新
        hematrix(col,row) = {hetermlist};
        hetermlist = {};
    end
end

% デバッグ用:
% orgmatrix
% hematrix


%% BMI一般化，Q,L,N,Rの取得
Q = linearmatrix; % 定数項，一次項
L = {}; % 双線形項の定数行列(左)
N = {}; % 双線形項の定数行列(中)
R = {}; % 双線形項の定数行列(右)


for col=1:size(orgmatrix,1)
    % 各行ベクトル
    for row=1:size(orgmatrix,2)
        % 各行列要素
        % disp(col+" "+row)
        termlist = orgmatrix{col,row};
        %
        xidx = 0; % 双線形項におけるXstrの位置
        yidx = 0; % 双線形項におけるYstrの位置
%         Llist = {}; % 一時リスト
%         Nlist = {}; 
%         Rlist = {}; 
        for i=1:size(termlist,1)
            % 要素の各項
            term = termlist{i,1};
            for j=1:size(term,2)
                % 項のそれぞれの変数
                var = term{1,j};
                if isequal(var, Xstr)
                    xidx = j;
                elseif isequal(var, Ystr) 
                    yidx = j;
                end
            end    
            % P,K(X,Y)でリストを3分割する
            l = term(1:xidx-1);
            n = term(xidx+1:yidx-1);
            r = term(yidx+1:end);
            % "PK"の場合： "1*P*1*K*1"と処理する
            if isempty(l) 
                l = {"1eye"};
            elseif l{1,1} == "-" && length(l) == 1
                l = ["-", "1eye"];
            end
            if isempty(n)
                n = {"1eye"};
            elseif n{1,1} == "-" && length(n) == 1
                n = ["-", "1eye"];
            end
            if isempty(r)
                r = {"1eye"};
            elseif r{1,1} == "-" && length(r) == 1
                r = ["-", "1eye"];
            end

            % L,N,Rの更新
            % 未完成(仮)
            % 双線形項が1行目にある場合にしか対応できない
            if col == 1                
                if isempty(L)
                    L = updateList(L,l);
                end
                N = {n};
                R = updateList(R,r,1);
            end
        end
        
        % 未完成(仮)
        if col == 1 && isempty(termlist)
            R = updateList(R,{"0zero"},1);
        end
        
%         L = updateList(L,Llist);
%         N = updateList(N,Nlist);
%         R = updateList(R,Rlist);
    end
    
    % 未完成(仮)
    if col >= 2
        L = updateList(L,{"0zero"},1);
    end
end

% デバッグ用:
% Q
% L,N,R


%% 逐次LMIに変形してCalc
% evalinを使う，workspaceの変数の値の取得
% 使用例:
%   evalin('base','X'): workspaceの変数名Xの値を取得する
%   evalin('base','eye(p1)'): workspaceの変数の値を使って関数eye(p1)を実行する


% ブロック行列のサイズの計算
% 制約行列の対角ブロックから割り出す
colsize = []; % 各ブロックの行サイズ
rowsize = []; % 各ブロックの列サイズ
for i=1:size(smatrix,1)
    idx = 1;
    s = smatrix{i,i}{1,1}{1,1};
    for j=1:size(smatrix,1)
        if s == "-"
            idx = idx+1;
            break
        end
    end
    s = smatrix{i,i}{1,1}{1,idx}; % 項の一番左の変数
    e = smatrix{i,i}{1,1}{1,end}; % 項の一番右の変数
    ssize = size(evalin('base',s),1);
    esize = size(evalin('base',e),2);
    colsize = cat(2,colsize,ssize);
    rowsize = cat(2,rowsize,esize);
end
% colsize,rowsize


% 線形項の計算
% cellQ = cellfun(@calclinear,Q,'UniformOutput',false);
cellQ = calclinear(Q,colsize,rowsize);
Qeval = cell2mat(cellQ);

% othermatlistの計算
% cellQother = cellfun(@calclinear,othermatlist,'UniformOutput',false);
cellQother = calclinear(othermatlist,colsize,rowsize);
Qothereval = cell2mat(cellQother);
% なければ0
if isempty(Qothereval)
    Qothereval = zeros(size(Qeval));
end

% matlistとothermatlistの計算結果を合計する
Qeval = Qeval + Qothereval;



% 受け取った引数がそもそもLMIの場合，そのまま計算結果を返す
% if isequal(cellfun(@isempty,binearmatrix),ones(size(binearmatrix)))
%     LMI = Qeval;
%     BMI = LMI;
%     return
% end


% 双線形項の左定数Lの計算
Leval = [];
for i=1:size(L,1)
    term = L{i,1};
    leval = 1; 
    for j=1:size(term,2)
        var = term{1,j};
        if var == "1eye"
            leval = leval * eye(size(X,1));
        elseif var == "0zero"
            leval = leval * zeros(rowsize(i),size(Leval,2));
        elseif var == "-"
            leval = -leval;
        else 
%             if regexp(var,'(?<!\D+)\d+')
%                 leval = leval * str2double(var);
%             else
%                 leval = leval * evalin('base', var);
%             end
            leval = leval * evalin('base', var);
        end
    end
    % 列(縦)ベクトルを生成
    Leval = cat(1,Leval,leval);
end
% Leval


% 双線形項の中定数Nの計算
Neval = [];
for i=1:size(N,1)
    term = N{i,1};
    neval = 1; 
    for j=1:size(term,2)
        var = term{1,j};
        if var == "1eye"
            neval = neval * eye(size(X,2),size(Y,1));
        elseif var == "-"
            neval = -neval;
        else
%             if regexp(var,'(?<!\D+)\d+')
%                 neval = neval * str2double(var);
%             else
%                 neval = neval * evalin('base', var);
%             end   
            neval = neval * evalin('base', var);
        end
    end
    Neval = neval;
end
% Neval


% 双線形項の右定数Rの計算
Reval = [];
for i=1:size(R,1)
    term = R{i,1};
    reval = 1; 
    for j=1:size(term,2)
        var = term{1,j};
        if var == "1eye"
            reval = reval * eye(size(Y,2));
        elseif var == "0zero"
            reval = reval * zeros(size(Reval,1),rowsize(i));
        elseif var == "-"
            reval = -reval;
        else
%             if regexp(var,'(?<!\D+)\d+')
%                 reval = reval * str2double(var);
%             else
%                 reval = reval * evalin('base', var);
%             end     
            reval = reval * evalin('base', var);
        end
    end
    % 行(横)ベクトルを生成
    Reval = cat(2,Reval,reval);
end
% Reval


% Leval
% Neval
% Reval
% X
% Y

% 双線形項の計算, LXNYR
Bieval = Leval * X * Neval * Y * Reval;

% Qeval
% Bieval

% BMIの値の計算, 多分使わない，デバッグ用
BMIeval = Qeval + Bieval + Bieval';



% 拡大した LMI 条件, heなし
% LMIeval=[Qeval+replace(Bieval,Y,Y0)+replace(Bieval,X,X0)-Leval*X0*Neval*Y0*Reval,...
%          Leval*(X-X0)*Neval;...
%          G*(Y-Y0)*Reval,...
%          -G];
% heあり

if isZ
% 分割行列も決定変数の場合(Zがある)
LMIeval = [Qeval+Leval*X*Neval*Y0*Reval+Leval*X0*Neval*Y*Reval-Leval*X0*Neval*Y0*Reval+...
    (Leval*X*Neval*Y0*Reval+Leval*X0*Neval*Y*Reval-Leval*X0*Neval*Y0*Reval)',... % (1,1)
     Leval*(X-X0)*Neval+(Z0*t*(Y-Y0)*Reval)',...     % (1,2)
    (Z0*(1-t)*(Y-Y0)*Reval)';...      % (1,3)
     Z0*t*(Y-Y0)*Reval+(Leval*(X-X0)*Neval)',...   % (2,1)
     -(Z+Z'),...                % (2,2)
     Z-Z0*t;...                      % (2,3)
     Z0*(1-t)*(Y-Y0)*Reval,...        % (3,1)
    (Z-Z0*t)',...                     % (3,2)
     -(Z0+Z0')*(1-t)];                % (3,3)

else
% 分割行列が定数行列の場合(Zなし)
LMIeval = [Qeval+Leval*X*Neval*Y0*Reval+Leval*X0*Neval*Y*Reval-Leval*X0*Neval*Y0*Reval+...
        (Leval*X*Neval*Y0*Reval+Leval*X0*Neval*Y*Reval-Leval*X0*Neval*Y0*Reval)',...% (1,1)
         Leval*(X-X0)*Neval+Reval'*(Y-Y0)'*G';...   % (1,2)
        (Leval*(X-X0)*Neval+Reval'*(Y-Y0)'*G')',... % (2,1)
         -(G+G')];                                  % (2,2)
end
     
%% For debug，Q,L,N,R,G's string
% represent by string list

Qchar = linear2str(Q,colsize,rowsize);


% L str
Lchar = [];
for i=1:length(L)
    var = L{i,1}{1,1};
    if var == "1eye"
        var = [func2str(@eye) '(' num2str(size(X,1)) ')'];
    elseif var == "0zero"
        var = [func2str(@zeros) '(' num2str(colsize(i)) ',' num2str(size(Leval,2)) ')'];
    end
    Lchar = [Lchar; string(var)];
end

% N str
Nchar = [];
for i=1:length(N)
    var = N{i,1}{1,1};
    if var == "1eye"
        var = [func2str(@eye) '(' num2str(size(X,2)) ',' num2str(size(Y,1)) ')'];
    end
    Nchar = [Nchar; string(var)];
end

% R str
Rchar = [];
for i=1:length(R)
    var = R{i,1}{1,1};
    if var == "1eye"
        var = [func2str(@eye) '(' num2str(size(Y,2)) ')'];
    elseif var == "0zero"
        var = [func2str(@zeros) '(' num2str(size(Y,1)) ',' num2str(rowsize(i)) ')'];
    end
    Rchar = [Rchar string(var)];
end


% Qchar, Lchar, Nchar, Rchar, Gchar
     
%% For debug，string of dilated LMI

% Qをheで分解する，転置を除く
HEQmatrix = Q; % 転置なし行列
HEQtermlist = {};    % 項のリスト(初期化)

for col=1:size(Q,1)
    % 各行ベクトル
    for row=1:size(Q,2)
        % 各行列要素
        % disp(col+" "+row)
        termlist = Q{col,row};
        for i=1:size(termlist,1)
            % 要素の各項
            term = termlist{i,1};
            for j=1:size(term,2)
                % 項のそれぞれの変数
                var = term{1,j};
                if regexp(var, "\'")
                    % var
                    % hetermlist: 転置あり
                    % hetermlist = updateList(hetermlist,term,1);
                    break
                else
                    % termlist: 転置なし
                    if col == row && col >= 2
                        % (2,2),(3,3)要素は1/2倍する
                        % スカラー倍を実装しないとできない
                        term = updateList(term,"0.5",2);
                    end
                    HEQtermlist = updateList(HEQtermlist,term,1);
                    break
                end
            end
        end
        % 転置なし行列の更新
        HEQmatrix(col,row) = {HEQtermlist};
        HEQtermlist = {};
    end
end
% HEQmatrix

% Q(str): no he ver
HEQchar = linear2str(HEQmatrix,colsize,rowsize);

% Create string of dilated LMI
% XNY_: X0_N_Y0 + (X-X0)_N_Y0 + X0_N_(Y-Y0)
Xchar = char(Xstr);
X0char = char(X0str);
Ychar = char(Ystr);
Y0char = char(Y0str);
X0_N_Y0 = [X0char '*' char(Nchar) '*' Y0char];
Xd_N_Y0 = ['(' Xchar '-' X0char ')' '*' char(Nchar) '*' Y0char];
X0_N_Yd = [X0char '*' char(Nchar) '*' '(' Ychar '-' Y0char ')'];
XNY_ = [X0_N_Y0 '+' Xd_N_Y0 '+' X0_N_Yd];
% L(XNY_)R
L_XNY_R = [];
for i=1:length(Lchar)
    list = [];
    for j=1:length(Rchar)
        if regexp(Lchar(i), "zeros")
            l = char(Lchar(i));
        elseif regexp(Rchar(i), "zeros")
            l = char(Rchar(i));
        elseif regexp(Lchar(i), "eye")
            l = ['comp*' char(Rchar(j))];
        elseif regexp(Rchar(i), "eye")
            l = ['comp*' char(Rchar(j))];
        elseif regexp(Lchar(i), "eye") && regexp(Rchar(i), "eye")
            l = 'comp';
        else
            l = [char(Lchar(i)) '*comp*' char(Rchar(j))];
        end
        list = [list string(l)];
    end
    L_XNY_R = [L_XNY_R; list];
end
% Q0 + L_XNY_R
QLXNYR = [];
for i=1:size(HEQchar,1)
    list = [];
    for j=1:size(HEQchar,2)
        heq = HEQchar(i,j);
        heq = regexprep(heq,Xstr,string(['(' Xchar '-' X0char ')']));
        heq = regexprep(heq,Ystr,string(['(' Ychar '-' Y0char ')']));
        
        if regexp(L_XNY_R(i,j), "zeros")
            l = char(heq);
        else
            l = [char(heq) '+' char(L_XNY_R(i,j))];
        end
        list = [list string(l)];
    end
    QLXNYR = [QLXNYR; list];
end

% LXN
LXN = [];
for i=1:length(Lchar)
    if regexp(Lchar(i), "zeros")
        l = regexprep( Lchar(i), ",\w)", ","+string(size(Neval,2))+")" );
    elseif regexp(Lchar(i), "eye")
        l = ['(' Xchar '-' X0char ')*' char(Nchar)];
    elseif regexp(Nchar(i), "eye")
        l = [char(Lchar(i)) '*(' Xchar '-' X0char ')'];
    elseif regexp(Lchar(i), "eye") && regexp(Rchar(i), "eye")
        l = [Xchar '-' X0char];
    else
        l = [char(Lchar(i)) '*(' Xchar '-' X0char ')*' char(Nchar)];
    end
    LXN = [LXN; string(l)];
end


if ~isZ
    % GYR
    GYR = [];
    for i=1:length(Rchar)
        if regexp(Rchar(i), "zeros")
            l = char(Rchar(i));
        elseif regexp(Gchar, "eye")
            l = ['(' Ychar '-' Y0char ')*' char(Rchar(i))];
        elseif regexp(Rchar(i), "eye")
            l = [char(Gchar) '*(' Ychar '-' Y0char ')'];
        elseif regexp(Gchar, "eye") && regexp(Rchar(i), "eye")
            l = [Ychar '-' Y0char];
        else
            l = [char(Gchar) '*(' Ychar '-' Y0char ')*' char(Rchar(i))];
        end
        GYR = [GYR string(l)];
    end
else
    % HYR
    HYR = [];
    Zchar = string(Zstr);
    Z0char = string(Z0str);
    for i=1:length(Rchar)
        if regexp(Rchar(i), "zeros")
            l = char(Rchar(i));
        elseif regexp(Z0char, "eye")
            l = ['(' Ychar '-' Y0char ')*' char(Rchar(i))];
        elseif regexp(Rchar(i), "eye")
            l = [char(Z0char) '*(' Ychar '-' Y0char ')'];
        elseif regexp(Z0char, "eye") && regexp(Rchar(i), "eye")
            l = [Ychar '-' Y0char];
        else
            l = [char(Z0char) '*(' Ychar '-' Y0char ')*' char(Rchar(i))];
        end
        HYR = [HYR string(l)];
    end

    % zeros
    % HYR'
    O1 = [];
    for i=1:length(Rchar)
        o = [func2str(@zeros) '(' num2str(colsize(i)) ',' num2str(size(Z,2)) ')'];
        O1 = [O1; string(o)];
    end
    % LXN'
    O2 = [];
    for i=1:length(Lchar)
        o = [func2str(@zeros) '(' num2str(size(Z,1)) ',' num2str(rowsize(i)) ')'];
        O2 = [O2 string(o)];
    end
    % Z'
    O3 = [func2str(@zeros) '(' num2str(size(Z,2)) ',' num2str(size(Z,1)) ')'];
end

% Dilated LMI
if isZ
    LMIstr = lmistr(QLXNYR, LXN, O1, O2, "-"+Zchar, Zchar, HYR, O3, "-"+Z0char, XNY_);
else
    LMIstr = lmistr(QLXNYR,LXN,GYR,"-"+Gchar,XNY_);
end



%% For Debug, general form BMI's infomations
%%%% No He()
% Q0= Qeval; % Linear term
% L = Leval; % Bilinear term's coefficient matrix(left)
% N = Neval; % ... (mid)
% R = Reval; % ... (right)

gBMI.expression = 'Q + He( L * X * N * Y * R )';

% sdpvar string
gBMI.sdpvar.expr = 'Q + He( L * X * N * Y * R )';
gBMI.sdpvar.msg = 'sdpvar as strings';
gBMI.sdpvar.X = [Xstr '-' X0str];
gBMI.sdpvar.Y = [Ystr '-' Y0str];
if isZ
    gBMI.sdpvar.Z = [Zstr '-' Z0str];
end

% yalmip data
gBMI.data.expr = 'Q + He( L * X * N * Y * R )';
gBMI.data.msg = 'data for each matrix';
gBMI.data.Q = Qeval;
gBMI.data.L = Leval;
gBMI.data.N = Neval;
gBMI.data.R = Reval;

% string
gBMI.str.expr = 'Q + He( L * X * N * Y * R )';
gBMI.str.msg = 'strings for each matrix';
gBMI.str.Q = Qchar;
gBMI.str.L = Lchar;
gBMI.str.N = Nchar;
gBMI.str.R = Rchar;


%% Output LMI data
% LMI = LMIeval + LMIeval';
% BMI = BMIeval + BMIeval';

LMI = LMIeval;
BMI = BMIeval;

end
