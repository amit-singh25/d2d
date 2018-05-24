% nohup matlab -nosplash < arCompileAllSetups_call.m > nohup.out &


function setup_files = arCompileAllSetups(recursive)
if ~exist('recursive','var') || isempty(recursive)
    recursive = true;
end


if recursive
    all_files = list_files_recursive;
else
    d = dir;
    files = {d.name};
    files = files(find(~[ d.isdir]));
    all_files = setdiff(files,{'.','..'});
end

if ~iscell(all_files)
    all_files = {all_files};
end

bol = false(size(all_files));
for i=1:length(all_files)
    [pathstr,name,ext] = fileparts(all_files{i});
    bol(i) = ~isempty(regexp(name,'^[sS]etup*')) && strcmp(ext,'.m')==1;
end

fidlog = fopen('arCompileAllSetups.log','w');

setup_files = all_files(bol);
fprintf('The following setup files were found and will be subsequently used for compiling: \n\n');
fprintf(fidlog,'The following setup files were found and will be subsequently used for compiling: \n\n');
for i=1:length(setup_files)
    fprintf('%s\n',setup_files{i});
    fprintf(fidlog,'%s\n',setup_files{i});
end
fprintf('\n\n');
fprintf(fidlog,'\n\n');

% create parallel pool if not yet existing:
p = gcp('nocreate');
if isempty(p)
    parpool('local')
end

pfad = pwd;

for i=1:length(setup_files)
    fprintf(fidlog,'%s will be executed ...\n\n' ,setup_files{i});
    [pathstr,name,ext] = fileparts(setup_files{i});
    cd(pathstr);
    
    try
        fid = fopen([name,ext], 'r');
        while (~feof(fid))
            [str, fid] = arTextScan(fid, '%s\n', 1, 'CommentStyle', '%');
            
            if ~isempty(str) && iscell(str)                
                if iscell(str)
                    str = strtrim(str{1});
                    if iscell(str)
                        str = strtrim(str{1});
                    end
                end
                if ~isempty(str) && ischar(str)
                    if ~isempty(regexp(str,'arInit'))
                        fprintf(fidlog,'%s\n',str);
                                eval(str);
                    elseif ~isempty(regexp(str,'arLoadModel\('))
                        fprintf(fidlog,'%s\n',str);
                                eval(str);
                    elseif ~isempty(regexp(str,'arLoadData\('))
                        fprintf(fidlog,'%s\n',str);
                                eval(str);
                    elseif ~isempty(regexp(str,'arCompileAll'))
                        fprintf(fidlog,'%s\n',str);
                                eval(str);
                    else
                        
                    end
                else
                    fprintf('Empty string str{1}= %s\n',str{1});
                end
            end
        end
        fprintf(fidlog,'\n\n');
        fclose(fid);
    catch ERR
        warning('\n%s failed !!!!!!!!! \n\n' ,setup_files{i});
        disp(lasterror);
        fprintf(fidlog,'\n%s failed !!!!!!!!! \n\n' ,setup_files{i});
        cd(pfad);
    end
end

fclose(fidlog);
cd(pfad)






