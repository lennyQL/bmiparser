function eval = calclinear(termlist)
% ���`���̊ecell�̗v�f���v�Z����֐�

    eval = 0;
    for i=1:size(termlist,1)
%         disp("----------")
        term = termlist{i,1};
        qeval = 1;
        for j=1:size(term,2)
            var = term{1,j};
            if var == "-"
                qeval = -qeval;
            else
    %                     if regexp(var,'(?<!\D+)\d+')
    %                         % ���l�̏ꍇ
    %                         qeval = qeval * str2double(var);
    %                     else
    %                         % �ϐ����̏ꍇ
    %                         qeval = qeval * evalin('base', var);
    %                     end
                qeval = qeval * evalin('base', var);
            end
        end
        eval = eval + qeval;
    end

    % �v�f�ɍ����Ȃ��ꍇ�C�[���s�������
    if isempty(termlist)
        eval = zeros(colsize(col),rowsize(row));
    end

end

