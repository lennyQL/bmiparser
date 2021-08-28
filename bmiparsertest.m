%% 出力フィードバック制御のBMI制約についてのテスト
%   bmiparserを評価するテストプログラム
%   Hinf問題，極配置問題2つの制約それぞれ評価する

% 次元
n =4; % xの次元,状態数
m1=3; % wの次元
m2=2; % uの次元,入力数
p1=3; % zの次元
p2=2; % yの次元,出力数

% 決定変数の宣言
X=sdpvar(n,n, 'full');
Y=sdpvar(m2,p2, 'full');
% BMI 決定変数の暫定値
X0=rand(size(X));
Y0=rand(size(Y));

% 一般化制御対象の係数行列
% random例
A=rand(n,n);
B1=rand(n,m1);
B2=rand(n,m2);
C1=rand(p1,n); 
C2=rand(p2,n);
D11=rand(p1,m1);
D12=rand(p1,m2);
D21=rand(p2,m1);
D22=rand(p2,m2);

% G,gammaの定数倍
G = eye(size(Y,1));
% 単位行列
I = eye(p1);
% ゼロ行列
O = zeros(p1);


%% Hinf問題, 制約がブロック行列の場合
disp("<<<======***** H無限大制御問題 *****======>>>")

%%%%%% 手計算 %%%%%%
% BMI制約
BMImanual = [X*A+X*B2*Y*C2+A'*X'+C2'*Y'*B2'*X'  X*B1+X*B2*Y*D21  C1'+C2'*Y'*D12';
             B1'*X'+D21'*Y'*B2'*X'               -I               D11'+D21'*Y'*D12';
             C1+D12*Y*C2                         D11+D12*Y*D21    -I];
% 線形項,heあり
Q0 = [X*A+A'*X'    X*B1           C1'+C2'*Y'*D12';
      B1'*X'       -I             D11'+D21'*Y'*D12';
      C1+D12*Y*C2  D11+D12*Y*D21    -I];
% 双線形項の定数行列,heなし
L = [eye(n,n);zeros(m1,n);zeros(p1,n)];
N = B2;
R = [C2 D21 zeros(p2,p1)];
% 手計算で導いた逐次LMI,heあり
LMImanual = [Q0+L*X*N*Y0*R+L*X0*N*Y*R-L*X0*N*Y0*R+(L*X*N*Y0*R+L*X0*N*Y*R-L*X0*N*Y0*R)',...
             L*(X-X0)*N+R'*(Y-Y0)'*G';...
            (L*(X-X0)*N+R'*(Y-Y0)'*G')',...
             -(G+G')];
         

         
%%%%%% parser(関数)による自動計算 %%%%%%%
% Hinf問題の制約の左辺，bmiparserのための制約の記述
% すべて等価な表現
%%% パターン1: 括弧()なし，1つの行列
Fstr1 = "[X*A+X*B2*Y*C2+A'*X'+C2'*Y'*B2'*X'  X*B1+X*B2*Y*D21  C1'+C2'*Y'*D12';"+...
        "B1'*X'+D21'*Y'*B2'*X'               -I               D11'+D21'*Y'*D12';"+...
        "C1+D12*Y*C2                         D11+D12*Y*D21    -I]";
%%% パターン2: 括弧()あり，1つの行列
Fstr = "[X*(A+B2*Y*C2)+(A+B2*Y*C2)'*X'  X*(B1+B2*Y*D21)  (C1+D12*Y*C2)';"+...
        "(B1+B2*Y*D21)'*X'               -I               (D11+D12*Y*D21)';"+...
        "C1+D12*Y*C2                     D11+D12*Y*D21    -I]";
%%% パターン3: 関数あり，1つの行列
Fstr3 = "[X*(A+B2*Y*C2)+(A+B2*Y*C2)'*X'  X*(B1+B2*Y*D21)     (C1+D12*Y*C2)';"+...
        "(B1+B2*Y*D21)'*X'               -eye(p1)+zeros(p1)  (D11+D12*Y*D21)';"+...
        "C1+D12*Y*C2                     D11+D12*Y*D21       -eye(p1,p1)*eye(p1)]";
%%% パターン4: 複数の行列の和
Fstr4 = "[[X*(A+B2*Y*C2)  X*(B1+B2*Y*D21)  zeros(n,p1);"+...
        "zeros(m1,n)     zeros(p1,m1)     zeros(m1,p1);"+...
        "zeros(p1,n)     zeros(p1,m1)     zeros(p1,p1)]"...     % 双線形項
        + "+" +...
        "[(A+B2*Y*C2)'*X'   zeros(n,m1)   zeros(n,p1);"+...
        "(B1+B2*Y*D21)'*X'  zeros(p1,m1)  zeros(m1,p1);"+...
        "zeros(p1,n)        zeros(p1,m1)  zeros(p1,p1)]"...     % 双線形項の転置
        + "+" +...
        "[zeros(n,n)   zeros(n,m1)    (C1+D12*Y*C2)';"+...
        "zeros(m1,n)   -eye(p1)       (D11+D12*Y*D21)';"+...
        "C1+D12*Y*C2   D11+D12*Y*D21  -eye(p1)]]";               % 線形項
%%% パターン5: ベクトル同士の積, 転置あり
Fstr5 = "[[X;zeros(m1,n);zeros(p1,n)]*[A+B2*Y*C2 B1+B2*Y*D21 zeros(n,p1)]"... % 双線形項
        +"+"+...
        "([X;zeros(m1,n);zeros(p1,n)]*[A+B2*Y*C2 B1+B2*Y*D21 zeros(n,p1)])'"... % 双線形項の転置
        + "+" +...
        "[zeros(n,n)   zeros(n,m1)    (C1+D12*Y*C2)';"+...
        "zeros(m1,n)   -eye(p1)       (D11+D12*Y*D21)';"+...
        "C1+D12*Y*C2   D11+D12*Y*D21  -eye(p1)]]";            % 線形項

% parser(自作した関数)
[LMIauto1, BMIauto1] = bmiparser(Fstr1,{'X','Y'},{'X0','Y0'});
[LMIauto2, BMIauto2, g] = bmiparser(Fstr,{'X','Y'},{'X0','Y0'});
[LMIauto3, BMIauto3] = bmiparser(Fstr3,{'X','Y'},{'X0','Y0'});
[LMIauto4, BMIauto4] = bmiparser(Fstr4,{'X','Y'},{'X0','Y0'});
[LMIauto5, BMIauto5] = bmiparser(Fstr5,{'X','Y'},{'X0','Y0'});

% Q0
% g.Q

%%%%% 評価 %%%%%
% BMItt: ゼロ行列かどうか
% LMItt: coefficient range < 1e-10 かどうか

disp(newline)
disp("###*** パターン1 ***###")
disp("# 括弧()なし，1つの行列による記述")
BMItt = BMImanual - BMIauto1
LMItt = LMImanual - LMIauto1

disp(newline)
disp("###*** パターン2 ***###")
disp("# 括弧()あり，1つの行列による記述")
BMItt = BMImanual - BMIauto2
LMItt = LMImanual - LMIauto2

disp(newline)
disp("###*** パターン3 ***###")
disp("# 関数あり，1つの行列")
BMItt = BMImanual - BMIauto3
LMItt = LMImanual - LMIauto3

disp(newline)
disp("###*** パターン4 ***###")
disp("# 複数の行列の和")
BMItt = BMImanual - BMIauto4
LMItt = LMImanual - LMIauto4

disp(newline)
disp("###*** パターン5 ***###")
disp("# ベクトル同士の積")
BMItt = BMImanual - BMIauto5
LMItt = LMImanual - LMIauto5


%% LMI
% F ="[[X;zeros(n,n)]*[A,A]+"+...
%     "([X;zeros(n,n)]*[A,A])']"
% 
% a = [[X;zeros(n,n)]*[A,A]+([X;zeros(n,n)]*[A,A])']
% b = bmiparser(F,{'X','Y'},{'X0','Y0'})
% a-b

%% 極配置問題, 制約がブロック行列で表されない場合
disp(newline)
disp("<<<======***** 極配置問題 *****======>>>")

% % BMI 制約式の左辺
% Fstr = "X*A+X*B2*Y*C2+A'*X'+C2'*Y'*B2'*X'";
Fstr = "X*(A+B2*Y*C2)+(A+B2*Y*C2)'*X'";
% Fstr = "eye(n)*X*(A+B2*Y*C2)+(A+B2*Y*C2)'*X'*eye(n,n)+(zeros(n)-zeros(n))*(zeros(n)+zeros(n))";
[LMIauto, BMIauto] = bmiparser(Fstr,{'X','Y'},{'X0','Y0'});
% 
% BMImanual = X*A+X*B2*Y*C2+A'*X'+C2'*Y'*B2'*X';
BMImanual = X*(A+B2*Y*C2)+(A+B2*Y*C2)'*X';
%
Q0 = X*A+A'*X';
L = eye(n,n);
N = B2;
R = C2;
%
LMImanual = [Q0+L*X*N*Y0*R+L*X0*N*Y*R-L*X0*N*Y0*R+(L*X*N*Y0*R+L*X0*N*Y*R-L*X0*N*Y0*R)',...
             L*(X-X0)*N+R'*(Y-Y0)'*G';...
            (L*(X-X0)*N+R'*(Y-Y0)'*G')',...
             -(G+G')];
%
disp("# 制約がブロック行列で表されない")
BMItt = BMImanual - BMIauto
LMItt = LMImanual - LMIauto

% [a,b,g] = bmiparser(Fstr,{'X','Y'},{'X0','Y0'});
% g

