function smatrix = rmngsign(termlist)
% ���̃}�C�i�X(-)�������팸

smatrix = {};

for i=1:size(termlist,1)
    % disp("----------")
    term = termlist{i,1};
    varlist = {};
    signcount = 0; % -�����̃J�E���^
    
    % �����T��
    for j=1:size(term,2)
        var = term{1,j};
        if var == "-"
            signcount = signcount + 1;
        else
            varlist = updateList(varlist,var);
        end
    end
    
    % -����Ȃ�C���̐擪��-��t����
    if mod(signcount,2) ~= 0
        varlist = cat(2,{["-"]},varlist);
    end
    
    % ���̃��X�g������(�c��cell�z��Ƃ���)
    smatrix = updateList(smatrix,varlist,1);
    
end


end

