function celleval = calclinear(smatrix,colsize,rowsize)
% ���`���̊ecell�̗v�f���v�Z����֐�

celleval = smatrix;

for col=1:size(smatrix,1)
    % �e�s�x�N�g��
    for row=1:size(smatrix,2)
        % �e�s��v�f
        % disp(col+" "+row)
        termlist = smatrix{col,row};
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
                    qeval = qeval * evalin('base', var);
                end
            end
            eval = eval + qeval;
        end

        % �v�f�ɍ����Ȃ��ꍇ�C�[���s�������
        if isempty(termlist)
            eval = zeros(colsize(col),rowsize(row));
        end
        
        celleval(col,row) = {eval};
        
    end
end

end

