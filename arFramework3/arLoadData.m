% Load data set to next free slot
%
% arLoadModel(name, m, d, extension, removeEmptyObs)
%
% name              filename of data definition file
% m                 target position for model                       [last]
% d                 target position for data (deprecated!!!)
% extension         data file name-extension: 'xls', 'csv'          ['xls']
%                   'none' = don't load data                           
% removeEmptyObs     remove observation without data                [false]
%
%
% In der ersten Spalte:
% 1)    Die Messzeitpunkte (duerfen mehrfach vorkommen).
%
% Danach in Spalten beliebiger Reihenfolge:
% 2)    Die experimentellen Bedingungen (z.B. "input_IL6" und "input_IL1").
% 3)    Die Datenpunkte fuer die einzelnen Spezies (z.B. "P_p38_rel").
%
% Anmerkungen:
% 1)    In Spaltenkoepfen duerfen keine Zeichen vorkommen die mathematischen
%       Operationen entsprechen (z.B. "-" oder "+").
% 2)    Ich habe Stimulationen immer den Praefix "input_" gegeben. Bei Spezies
%       bedeuten die Suffixe "_rel" und "_au": relative Phosphorylierung und
%       arbitrary units, je nachdem.
%
% Copyright Andreas Raue 2011 (andreas.raue@fdm.uni-freiburg.de)

function arLoadData(name, m, d, extension, removeEmptyObs, dpPerShoot)

global ar

if(isempty(ar))
    error('please initialize by arInit')
end

% load model from mat-file
if(~exist('Data','dir'))
    error('folder Data/ does not exist')
end
if(~exist(['Data/' name '.def'],'file'))
    error('data definition file %s.def does not exist in folder Data/', name)
end

if(~exist('m','var') || isempty(m))
    m = length(ar.model);
end

if(exist('d','var') && ~isempty(d))
    warning('arLoadData(name, m, d, ... input argument d is deprecated !!!'); %#ok<WNTAG>
end
if(isfield(ar.model(m), 'data'))
    d = length(ar.model(m).data) + 1;
else
    ar.model(m).data = [];
    d = 1;
end

if(~exist('extension','var'))
    extension = 'xls';
end
if(~exist('removeEmptyObs','var'))
    removeEmptyObs = false;
end

if(exist('dpPerShoot','var') && dpPerShoot>0)
    if(~isfield(ar,'ms_count_snips'))
        ar.model(m).ms_count = 0;
        ar.ms_count_snips = 0;
        ar.ms_strength = 0;
        ar.ms_threshold = 1e-5;
        ar.ms_violation = [];
    end
else
    dpPerShoot = 0;
end

% initial setup
ar.model(m).data(d).name = strrep(strrep(strrep(strrep(name,'=','_'),'.',''),'-','_'),'/','_');

fprintf('\nloading data #%i, from file Data/%s.def ...', d, name);
fid = fopen(['Data/' name '.def'], 'r');

% DESCRIPTION
str = textscan(fid, '%s', 1, 'CommentStyle', ar.config.comment_string);
if(~strcmp(str{1},'DESCRIPTION'))
    error('parsing data %s for DESCRIPTION', name);
end
str = textscan(fid, '%q', 1, 'CommentStyle', ar.config.comment_string);
ar.model(m).data(d).description = {};
while(~strcmp(str{1},'PREDICTOR') && ~strcmp(str{1},'PREDICTOR-DOSERESPONSE'))
    ar.model(m).data(d).description(end+1,1) = str{1}; %#ok<*AGROW>
    str = textscan(fid, '%q', 1, 'CommentStyle', ar.config.comment_string);
end

% PREDICTOR
if(strcmp(str{1},'PREDICTOR-DOSERESPONSE'))
    ar.model(m).data(d).doseresponse = true;
    str = textscan(fid, '%s', 1, 'CommentStyle', ar.config.comment_string);
    ar.model(m).data(d).response_parameter = cell2mat(str{1});
    fprintf('dose-response to %s\n', ar.model(m).data(d).response_parameter);
else
    ar.model(m).data(d).doseresponse = false;
    fprintf('\n');
end
C = textscan(fid, '%s %s %q %q %n %n %n %n\n',1, 'CommentStyle', ar.config.comment_string);
ar.model(m).data(d).t = cell2mat(C{1});
ar.model(m).data(d).tUnits(1) = C{2};
ar.model(m).data(d).tUnits(2) = C{3};
ar.model(m).data(d).tUnits(3) = C{4};
ar.model(m).data(d).tLim = [C{5} C{6}];
ar.model(m).data(d).tLimExp = [C{7} C{8}];
if(isnan(ar.model(m).tLim(1)))
    ar.model(m).tLim(1) = 0;
end
if(isnan(ar.model(m).tLim(2)))
    ar.model(m).tLim(2) = 10;
end
if(isnan(ar.model(m).data(d).tLimExp(1)))
    ar.model(m).data(d).tLimExp(1) = ar.model(m).tLim(1);
end
if(isnan(ar.model(m).data(d).tLimExp(2)))
    ar.model(m).data(d).tLimExp(2) = ar.model(m).tLim(2);
end

% INPUTS
str = textscan(fid, '%s', 1, 'CommentStyle', ar.config.comment_string);
if(~strcmp(str{1},'INPUTS'))
    error('parsing data %s for INPUTS', name);
end
C = textscan(fid, '%s %q\n',1, 'CommentStyle', ar.config.comment_string);
ar.model(m).data(d).fu = ar.model(m).fu;
while(~strcmp(C{1},'OBSERVABLES'))
    qu = ismember(ar.model(m).u, C{1});
    if(sum(qu)~=1)
        error('unknown input %s', cell2mat(C{1}));
    end
    ar.model(m).data(d).fu(qu) = C{2};
    
    C = textscan(fid, '%s %q\n',1, 'CommentStyle', ar.config.comment_string);
end

% input parameters
varlist = cellfun(@symvar, ar.model(m).data(d).fu, 'UniformOutput', false);
ar.model(m).data(d).pu = setdiff(vertcat(varlist{:}), {ar.model(m).t, ''});

% OBSERVABLES
ar.model(m).data(d).y = {};
ar.model(m).data(d).yNames = {};
ar.model(m).data(d).yUnits = {};
ar.model(m).data(d).normalize = [];
ar.model(m).data(d).logfitting = [];
ar.model(m).data(d).logplotting = [];
ar.model(m).data(d).fy = {};
C = textscan(fid, '%s %q %q %q %n %n %q %q\n',1, 'CommentStyle', ar.config.comment_string);
while(~strcmp(C{1},'ERRORS'))
    ar.model(m).data(d).y(end+1) = C{1};
    ar.model(m).data(d).yUnits(end+1,1) = C{2};
    ar.model(m).data(d).yUnits(end,2) = C{3};
    ar.model(m).data(d).yUnits(end,3) = C{4};
    ar.model(m).data(d).normalize(end+1) = C{5};
    ar.model(m).data(d).logfitting(end+1) = C{6};
    ar.model(m).data(d).logplotting(end+1) = C{6};
    ar.model(m).data(d).fy(end+1,1) = C{7};
    if(~isempty(cell2mat(C{8})))
        ar.model(m).data(d).yNames(end+1) = C{8};
    else
        ar.model(m).data(d).yNames(end+1) = ar.model(m).data(d).y(end);
    end
    C = textscan(fid, '%s %q %q %q %n %n %q %q\n',1, 'CommentStyle', ar.config.comment_string);
    if(sum(ismember(ar.model(m).x, ar.model(m).data(d).y{end}))>0)
        error('%s already defined in STATES', ar.model(m).data(d).y{end});
    end
end

% observation parameters
varlist = cellfun(@symvar, ar.model(m).data(d).fy, 'UniformOutput', false);
ar.model(m).data(d).py = setdiff(setdiff(vertcat(varlist{:}), union(ar.model(m).x, ar.model(m).u)), {ar.model(m).t, ''});
for j=1:length(ar.model(m).data(d).fy)
    varlist = symvar(ar.model(m).data(d).fy{j});
    ar.model(m).data(d).py_sep(j).pars = setdiff(setdiff(varlist, union(ar.model(m).x, ar.model(m).u)), {ar.model(m).t, ''});
end

% ERRORS
ar.model(m).data(d).fystd = cell(size(ar.model(m).data(d).fy));
errors_assigned = false(size(ar.model(m).data(d).fy));
C = textscan(fid, '%s %q\n',1, 'CommentStyle', ar.config.comment_string);
while(~strcmp(C{1},'INVARIANTS'))
    qy = ismember(ar.model(m).data(d).y, C{1});
    if(sum(qy)~=1)
        error('unknown observable %s', cell2mat(C{1}));
    end
    ar.model(m).data(d).fystd(qy) = C{2};
    errors_assigned(qy) = true;
    C = textscan(fid, '%s %q\n',1, 'CommentStyle', ar.config.comment_string);
end

if(length(ar.model(m).data(d).fystd)<length(ar.model(m).data(d).fy) || sum(~errors_assigned) > 0)
    error('some observables do not have an defined error model');
end

% error parameters
varlist = cellfun(@symvar, ar.model(m).data(d).fystd, 'UniformOutput', false);
ar.model(m).data(d).pystd = setdiff(vertcat(varlist{:}), union(union(union(ar.model(m).x, ar.model(m).u), ...
    ar.model(m).data(d).y), ar.model(m).t));
for j=1:length(ar.model(m).data(d).fystd)
    varlist = symvar(ar.model(m).data(d).fystd{j});
    ar.model(m).data(d).py_sep(j).pars = union(ar.model(m).data(d).py_sep(j).pars, ...
        setdiff(varlist, union(ar.model(m).x, ar.model(m).u)));
end

% INVARIANTS
ar.model(m).data(d).fxeq = ar.model(m).fxeq;
C = textscan(fid, '%q\n',1, 'CommentStyle', ar.config.comment_string);
while(~strcmp(C{1},'CONDITIONS'))
    if(~strcmp(C{1},''))
        ar.model(m).data(d).fxeq(end+1) = C{1};
    end
    C = textscan(fid, '%q\n',1, 'CommentStyle', ar.config.comment_string);
end

% extra invariational parameters
varlist = cellfun(@symvar, ar.model(m).data(d).fxeq, 'UniformOutput', false);
ar.model(m).data(d).pxeq = setdiff(vertcat(varlist{:}), union(ar.model(m).x, union(ar.model(m).u, ...
    ar.model(m).px)));

% TODO solve for invariants

% collect parameters needed for OBS
ar.model(m).data(d).p = union(ar.model(m).p, union(ar.model(m).data(d).pu, ar.model(m).data(d).py));
ar.model(m).data(d).p = union(ar.model(m).data(d).p, union(ar.model(m).data(d).pystd, ar.model(m).data(d).pxeq));

% CONDITIONS
C = textscan(fid, '%s %q\n',1, 'CommentStyle', ar.config.comment_string);
ar.model(m).data(d).fp = transpose(ar.model(m).data(d).p);
qcondparamodel = ismember(ar.model(m).data(d).p, ar.model(m).p);
ar.model(m).data(d).fp(qcondparamodel) = ar.model(m).fp;
while(~isempty(C{1}) && ~strcmp(C{1},'RANDOM'))
    qcondpara = ismember(ar.model(m).data(d).p, C{1});
    if(sum(qcondpara)>0)
        ar.model(m).data(d).fp{qcondpara} = ['(' cell2mat(C{2}) ')'];
    else
        error('unknown parameter in conditions %s', cell2mat(C{1}));
    end
    C = textscan(fid, '%s %q\n',1, 'CommentStyle', ar.config.comment_string);
end

% extra conditional parameters
varlist = cellfun(@symvar, ar.model(m).data(d).fp, 'UniformOutput', false);
ar.model(m).data(d).pcond = setdiff(vertcat(varlist{:}), ar.model(m).data(d).p);

% collect parameters conditions
pcond = union(ar.model(m).data(d).p, ar.model(m).data(d).pcond);

% RANDOM
ar.model(m).data(d).prand = {};
ar.model(m).data(d).rand_type = [];
C = textscan(fid, '%s %s\n',1, 'CommentStyle', ar.config.comment_string);
while(~isempty(C{1}) && ~strcmp(C{1},'PARAMETERS'))
    ar.model(m).data(d).prand{end+1} = cell2mat(C{1});
    if(strcmp(C{2}, 'INDEPENDENT'))
        ar.model(m).data(d).rand_type(end+1) = 0;
    else
        warning('unknown random type %s', cell2mat(C{2}));  %#ok<WNTAG>
    end
    C = textscan(fid, '%s %s\n',1, 'CommentStyle', ar.config.comment_string);
end

% PARAMETERS
if(~isfield(ar, 'pExternLabels'))
    ar.pExternLabels = {};
    ar.pExtern = [];
    ar.qFitExtern = [];
    ar.qLog10Extern = [];
    ar.lbExtern = [];
    ar.ubExtern = [];
end
C = textscan(fid, '%s %f %n %n %n %n\n',1, 'CommentStyle', ar.config.comment_string);
while(~isempty(C{1}))
    ar.pExternLabels(end+1) = C{1};
    ar.pExtern(end+1) = C{2};
    ar.qFitExtern(end+1) = C{3};
    ar.qLog10Extern(end+1) = C{4};
    ar.lbExtern(end+1) = C{5};
    ar.ubExtern(end+1) = C{6};
    C = textscan(fid, '%s %f %n %n %n %n\n',1, 'CommentStyle', ar.config.comment_string);
end

% plot setup
if(isfield(ar.model(m).data(d), 'response_parameter') && ...
        ~isempty(ar.model(m).data(d).response_parameter))
    if(sum(ismember(ar.model(m).data(d).p ,ar.model(m).data(d).response_parameter))==0 && ...
            sum(ismember(ar.model(m).data(d).pcond ,ar.model(m).data(d).response_parameter))==0)
        error('invalid response parameter %s', ar.model(m).data(d).response_parameter);
    end
end
if(~isfield(ar.model(m), 'plot'))
    ar.model(m).plot(1).name = strrep(strrep(strrep(strrep(name,'=','_'),'.',''),'-','_'),'/','_');
else
    ar.model(m).plot(end+1).name = strrep(strrep(strrep(strrep(name,'=','_'),'.',''),'-','_'),'/','_');
end
ar.model(m).plot(end).doseresponse = ar.model(m).data(d).doseresponse;
ar.model(m).plot(end).dLink = d;
ar.model(m).plot(end).dColor = 1;
ar.model(m).plot(end).ny = length(ar.model(m).data(d).y);
ar.model(m).plot(end).condition = {};
jplot = length(ar.model(m).plot);

fclose(fid);

% XLS file
if(~strcmp(extension,'none') && ((exist(['Data/' name '.xls'],'file') && strcmp(extension,'xls')) || ...
        (exist(['Data/' name '.csv'],'file') && strcmp(extension,'csv'))))
    fprintf('loading data #%i, from file Data/%s.%s ...\n', d, name, extension);
    
    % read from file
    if(strcmp(extension,'xls'))
        warntmp = warning;
        warning('off','all')
        [data, Cstr] = xlsread(['Data/' name '.xls']);
        warning(warntmp);
        
        header = Cstr(1,2:end);
        times = data(:,1);
        qtimesnonnan = ~isnan(times);
        times = times(qtimesnonnan);
        data = data(qtimesnonnan,2:end);
        if(size(data,2)<length(header))
            data = [data nan(size(data,1),length(header)-size(data,2))];
        end
    elseif(strcmp(extension,'csv'))
        fid = fopen(['Data/' name '.csv'], 'r');
        
        C = textscan(fid,'%s\n',1);
        C = textscan(C{1}{1},'%q','Delimiter',',');
        C = C{1};
        header = C(2:end)';
        
        data = nan(0, length(header));
        times = [];
        rcount = 1;
        C = textscan(fid,'%q',length(header)+1,'Delimiter',',');
        while(~isempty(C{1}))
            C = strrep(C{1}',',','.');
            times(rcount,1) = str2double(C{1});
            for j=1:length(header)
                data(rcount,j) = str2double(C{j+1});
            end
            C = textscan(fid,'%q',length(header)+1,'Delimiter',',');
            rcount = rcount + 1;
        end
        
        fclose(fid);
    end
    
    % random effects
    qrandis = ismember(header, ar.model(m).data(d).prand);
    if(sum(qrandis) > 0)
        qobs = ismember(header, ar.model(m).data(d).y);
        randis_header = header(qrandis);
        [randis, irandis, jrandis] = unique(data(:,qrandis),'rows');  %#ok<ASGLU>
        for j=1:size(randis,1)
            qvals = jrandis == j;
            tmpdata = data(qvals,qobs);
            if(sum(~isnan(tmpdata(:)))>0)
                fprintf('local random effect #%i:\n', j)
                
                if(j < size(randis,1))
                    ar.model(m).data(d+1) = ar.model(m).data(d);
                    ar.model(m).plot(jplot+1) = ar.model(m).plot(jplot);
                end
                
                for jj=1:size(randis,2)
                    fprintf('\t%20s = %g\n', randis_header{jj}, randis(j,jj))
                    
                    ar.model(m).plot(jplot).name = [ar.model(m).plot(jplot).name '_' ...
                        randis_header{jj} sprintf('%04i',randis(j,jj))];
                    
                    ar.model(m).data(d).name = [ar.model(m).data(d).name '_' ...
                        randis_header{jj} sprintf('%04i',randis(j,jj))];
                    
                    ar.model(m).data(d).fy = strrep(ar.model(m).data(d).fy, ...
                        randis_header{jj}, [randis_header{jj} sprintf('%04i',randis(j,jj))]);
                    ar.model(m).data(d).py = strrep(ar.model(m).data(d).py, ...
                        randis_header{jj}, [randis_header{jj} sprintf('%04i',randis(j,jj))]);
                    
                    ar.model(m).data(d).fystd = strrep(ar.model(m).data(d).fystd, ...
                        randis_header{jj}, [randis_header{jj} sprintf('%04i',randis(j,jj))]);
                    ar.model(m).data(d).pystd = strrep(ar.model(m).data(d).pystd, ...
                        randis_header{jj}, [randis_header{jj} sprintf('%04i',randis(j,jj))]);
                    
                    ar.model(m).data(d).fxeq = strrep(ar.model(m).data(d).fxeq, ...
                        randis_header{jj}, [randis_header{jj} sprintf('%04i',randis(j,jj))]);
                    ar.model(m).data(d).pxeq = strrep(ar.model(m).data(d).pxeq, ...
                        randis_header{jj}, [randis_header{jj} sprintf('%04i',randis(j,jj))]);
                    
                    ar.model(m).data(d).p = strrep(ar.model(m).data(d).p, ...
                        randis_header{jj}, [randis_header{jj} sprintf('%04i',randis(j,jj))]);
                    ar.model(m).data(d).fp = strrep(ar.model(m).data(d).fp, ...
                        randis_header{jj}, [randis_header{jj} sprintf('%04i',randis(j,jj))]);
                    ar.model(m).data(d).pcond = strrep(ar.model(m).data(d).pcond, ...
                        randis_header{jj}, [randis_header{jj} sprintf('%04i',randis(j,jj))]);
                    
                    for jjj=1:length(ar.model(m).data(d).py_sep)
                        ar.model(m).data(d).py_sep(jjj).pars = strrep(ar.model(m).data(d).py_sep(jjj).pars, ...
                            randis_header{jj}, [randis_header{jj} sprintf('%04i',randis(j,jj))]);
                    end
                end
               
                [ar,d] = setConditions(ar, m, d, jplot, header, times(qvals), data(qvals,:), ...
                    strrep(pcond, randis_header{jj}, [randis_header{jj} num2str(randis(j,jj))]), removeEmptyObs, dpPerShoot);
                
                if(j < size(randis,1))
                    d = d + 1;
                    jplot = jplot + 1;
                    ar.model(m).plot(jplot).dLink = d;
                    ar.model(m).plot(jplot).dColor = 1;
                end
            else
                fprintf('local random effect #%i: no matching data, skipped\n', j);
            end
        end
    else
        ar = setConditions(ar, m, d, jplot, header, times, data, pcond, removeEmptyObs, dpPerShoot);
    end
else
    ar.model(m).data(d).condition = [];
end



function [ar,d] = setConditions(ar, m, d, jplot, header, times, data, pcond, removeEmptyObs, dpPerShoot)
% normalization of columns
nfactor = max(data, [], 1);

qobs = ismember(header, ar.model(m).data(d).y) & sum(~isnan(data),1)>0;
qhasdata = ismember(ar.model(m).data(d).y, header(qobs));

% conditions
qcond = ismember(header, pcond);
if(sum(qcond) > 0)
    condi_header = header(qcond);
    qnonnanconds = sum(isnan(data(:,qcond)),2) == 0;
    [condis, icondis, jcondis] = unique(data(qnonnanconds,qcond),'rows');  %#ok<ASGLU>
    
    active_condi = false(size(condis(1,:)));
    tmpcondi = condis(1,:);
    for j=2:size(condis,1)
        active_condi = active_condi | (tmpcondi ~= condis(j,:));
    end
    
    for j=1:size(condis,1)
        
        fprintf('local condition #%i:\n', j)
        
        if(j < size(condis,1))
            if(length(ar.model(m).data) > d)
                ar.model(m).data(d+2) = ar.model(m).data(d+1);
            end
            ar.model(m).data(d+1) = ar.model(m).data(d);
        end
        
        % remove obs without data
        if(removeEmptyObs)
            for jj=find(~qhasdata)
                fprintf('\t%20s no data, removed\n', ar.model(m).data(d).y{jj});
                for jjj=find(ismember(ar.model(m).data(d).p, ar.model(m).data(d).py_sep(jj).pars))
                    jnotremove = [];
                    for jjjj = find(qhasdata)
                        jnotremove = unique([jnotremove find(ismember(ar.model(m).data(d).py_sep(jjjj).pars, ar.model(m).data(d).py_sep(jj).pars), 1)]);
                    end
                    ar.model(m).data(d).fp{setdiff(jjj,jnotremove)} = '0';
                end
            end
            ar.model(m).data(d).y = ar.model(m).data(d).y(qhasdata);
            ar.model(m).data(d).yNames = ar.model(m).data(d).yNames(qhasdata);
            ar.model(m).data(d).yUnits = ar.model(m).data(d).yUnits(qhasdata,:);
            ar.model(m).data(d).normalize = ar.model(m).data(d).normalize(qhasdata);
            ar.model(m).data(d).logfitting = ar.model(m).data(d).logfitting(qhasdata);
            ar.model(m).data(d).logplotting = ar.model(m).data(d).logplotting(qhasdata);
            ar.model(m).data(d).fy = ar.model(m).data(d).fy(qhasdata);
            ar.model(m).data(d).fystd = ar.model(m).data(d).fystd(qhasdata);
        end
        
        for jj=1:size(condis,2)
            fprintf('\t%20s = %g\n', condi_header{jj}, condis(j,jj))
            
            qcondjj = ismember(ar.model(m).data(d).p, condi_header{jj});
            if(sum(qcondjj)>0)
                ar.model(m).data(d).fp{qcondjj} = num2str(condis(j,jj));
            end
            qcondjj = ~strcmp(ar.model(m).data(d).p, ar.model(m).data(d).fp');
            ar.model(m).data(d).fp(qcondjj) = strrep(ar.model(m).data(d).fp(qcondjj), ...
                condi_header{jj}, num2str(condis(j,jj)));
           
            ar.model(m).data(d).condition(jj).parameter = condi_header{jj};
            ar.model(m).data(d).condition(jj).value = num2str(condis(j,jj));
            
            % plot
            if(active_condi(jj))
                if(ar.model(m).data(d).doseresponse==0 || ~strcmp(condi_header{jj}, ar.model(m).data(d).response_parameter))
                    if(length(ar.model(m).plot(jplot).condition) >= j && ~isempty(ar.model(m).plot(jplot).condition{j}))
                        ar.model(m).plot(jplot).condition{j} = [ar.model(m).plot(jplot).condition{j} ' & ' ...
                            ar.model(m).data(d).condition(jj).parameter '=' ...
                            ar.model(m).data(d).condition(jj).value];
                    else
                        ar.model(m).plot(jplot).condition{j} = [ar.model(m).data(d).condition(jj).parameter '=' ...
                            ar.model(m).data(d).condition(jj).value];
                    end
                end
            end
        end
        
        qvals = jcondis == j;
        ar = setValues(ar, m, d, header, nfactor, data(qvals,:), times(qvals));
        ar.model(m).data(d).tLim(2) = round(max(times)*1.1);
        
        if(dpPerShoot~=0)
            [ar,d] = doMS(ar,m,d,jplot,dpPerShoot);
        end
        
        if(j < size(condis,1))
            d = d + 1;
            ar.model(m).plot(jplot).dLink(end+1) = d;
            ar.model(m).plot(jplot).dColor(end+1) = ar.model(m).plot(jplot).dColor(end)+1;
        end
    end
else
    ar.model(m).data(d).condition = [];
    
    % remove obs without data
    if(removeEmptyObs)
        for jj=find(~qhasdata)
            fprintf('\t%20s no data, removed\n', ar.model(m).data(d).y{jj});
            for jjj=find(ismember(ar.model(m).data(d).p, ar.model(m).data(d).py_sep(jj).pars))
                remove = 1;
                for jjjj = find(qhasdata)
                    if ~isempty(find(ismember(ar.model(m).data(d).py_sep(jjjj).pars, ar.model(m).data(d).py_sep(jj).pars), 1))
                        remove = 0;
                    end
                end
                if remove
                    ar.model(m).data(d).fp{jjj} = '0';
                end
            end
        end
        ar.model(m).data(d).y = ar.model(m).data(d).y(qhasdata);
        ar.model(m).data(d).yNames = ar.model(m).data(d).yNames(qhasdata);
        ar.model(m).data(d).yUnits = ar.model(m).data(d).yUnits(qhasdata,:);
        ar.model(m).data(d).normalize = ar.model(m).data(d).normalize(qhasdata);
        ar.model(m).data(d).logfitting = ar.model(m).data(d).logfitting(qhasdata);
        ar.model(m).data(d).logplotting = ar.model(m).data(d).logplotting(qhasdata);
        ar.model(m).data(d).fy = ar.model(m).data(d).fy(qhasdata);
        ar.model(m).data(d).fystd = ar.model(m).data(d).fystd(qhasdata);
    end
    
    ar = setValues(ar, m, d, header, nfactor, data, times);
    
    if(dpPerShoot~=0)
        [ar,d] = doMS(ar,m,d,jplot,dpPerShoot);
    end
end


function [ar,d] = doMS(ar,m,d,jplot,dpPerShoot)

tExp = ar.model(m).data(d).tExp;

if(dpPerShoot ~= 1)
    nints = ceil(length(tExp) / dpPerShoot);
    tboarders = linspace(min(tExp),max(tExp),nints+1);
else
    tboarders = union(0,tExp);
    nints = length(tboarders)-1;
end

if(nints==1)
    return;
end

fprintf('using %i shooting intervals\n', nints);
ar.model(m).ms_count = ar.model(m).ms_count + 1;
ar.model(m).data(d).ms_index = ar.model(m).ms_count;

for j=1:nints
    ar.model(m).data(d).ms_snip_index = j;
    if(j<nints)
        ar.model(m).data(end+1) = ar.model(m).data(d);
        ar.model(m).plot(jplot).dLink(end+1) = d+1;
        ar.model(m).plot(jplot).dColor(end+1) = ar.model(m).plot(jplot).dColor(end);
    end
    
    if(j>1)
        ar.ms_count_snips = ar.ms_count_snips + 1;       
        qtodo = ismember(ar.model(m).data(d).p, ar.model(m).px0);
        ar.model(m).data(d).fp(qtodo) = strrep(ar.model(m).data(d).p(qtodo), 'init_', sprintf('init_MS%i_', ar.ms_count_snips));
    end
    
    if(j<nints)
        ar.model(m).data(d).tExp = ar.model(m).data(d).tExp(tExp>=tboarders(j) & tExp<tboarders(j+1));
        ar.model(m).data(d).yExp = ar.model(m).data(d).yExp(tExp>=tboarders(j) & tExp<tboarders(j+1),:);
        ar.model(m).data(d).yExpStd = ar.model(m).data(d).yExpStd(tExp>=tboarders(j) & tExp<tboarders(j+1),:);
    else
        ar.model(m).data(d).tExp = ar.model(m).data(d).tExp(tExp>=tboarders(j) & tExp<=tboarders(j+1));
        ar.model(m).data(d).yExp = ar.model(m).data(d).yExp(tExp>=tboarders(j) & tExp<=tboarders(j+1),:);
        ar.model(m).data(d).yExpStd = ar.model(m).data(d).yExpStd(tExp>=tboarders(j) & tExp<=tboarders(j+1),:);
    end
    
    ar.model(m).data(d).tLim = [tboarders(j) tboarders(j+1)];
    ar.model(m).data(d).tLimExp = ar.model(m).data(d).tLim;
    
    if(j<nints)
        d = d + 1;
    end
end


function ar = setValues(ar, m, d, header, nfactor, data, times)
ar.model(m).data(d).tExp = times;
ar.model(m).data(d).yExp = nan(length(times), length(ar.model(m).data(d).y));
ar.model(m).data(d).yExpStd = nan(length(times), length(ar.model(m).data(d).y));

for j=1:length(ar.model(m).data(d).y)
    q = ismember(header, ar.model(m).data(d).y{j});
    
    if(sum(q)==1)
        ar.model(m).data(d).yExp(:,j) = data(:,q);
        fprintf('\t%20s -> %4i data-points assigned', ar.model(m).data(d).y{j}, sum(~isnan(data(:,q))));
        
        % normalize data
        if(ar.model(m).data(d).normalize(j))
            ar.model(m).data(d).yExp(:,j) = ar.model(m).data(d).yExp(:,j) / nfactor(q);
            fprintf(' normalized');
        end
        
        % log-fitting
        if(ar.model(m).data(d).logfitting(j))
            ar.model(m).data(d).yExp(:,j) = log10(ar.model(m).data(d).yExp(:,j));
            fprintf(' for log-fitting');
        end
        
        % empirical stds
        qstd = ismember(header, [ar.model(m).data(d).y{j} '_std']);
        if(sum(qstd)==1)
            ar.model(m).data(d).yExpStd(:,j) = data(:,qstd);
            fprintf(' with stds');
            if(ar.model(m).data(d).normalize(j))
                ar.model(m).data(d).yExpStd(:,j) = ar.model(m).data(d).yExpStd(:,j) / nfactor(q);
                fprintf(' normalized');
            end
        elseif(sum(qstd)>1)
            error('multiple std colums for observable %s', ar.model(m).data(d).y{j})
        end
        
    elseif(sum(q)==0)
        fprintf('*\t%20s -> not assigned', ar.model(m).data(d).y{j});
    else
        error('multiple data colums for observable %s', ar.model(m).data(d).y{j})
    end
    
    fprintf('\n');
end

