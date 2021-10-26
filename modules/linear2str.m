function Qchar = linear2str(Q,colsize,rowsize)
% ���`��Q�̕������Ԃ��֐�(cell�z����󂯎��)

% Q�̕�����
Qchar = [];

for col=1:size(Q,1)
    % �e�s
    
    Qcharcol = [];
    for row=1:size(Q,2)
        % �e��
        termlist = Q{col,row};
        Qcharrow = [];
        for i=1:size(termlist,1)
            % �e�v�f
            term = termlist{i,1};
            qchar = [];
            for j=1:size(term,2)
                % �e��
                var = term{1,j};
                if isempty(qchar)
                    qchar = [qchar char(var)];
                elseif qchar == '-'
                    % qchar = ['(' qchar char(var) ')'];
                    qchar = [qchar char(var)];
                else
                    qchar = [qchar '*' char(var)];
                end
            end
            
            % �v�f���̍���+�œ���
            if isempty(Qcharrow)
                Qcharrow = [Qcharrow qchar];
            else
                Qcharrow = [Qcharrow '+' qchar];
            end
        end

        % �v�f�ɍ����Ȃ��ꍇ�C�[���s�������
        if isempty(termlist)
            var = [func2str(@zeros) '(' num2str( colsize(col) ) ',' num2str( rowsize(row) ) ')'];
            Qcharrow = [Qcharrow  var];
        end
        
        % ��̕���
        Qcharcol = [Qcharcol string(Qcharrow)];
        
    end
    % �s�̕���
    Qchar = [Qchar ; Qcharcol];
end


end

