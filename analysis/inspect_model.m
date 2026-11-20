% Inspect wiring of Estimationdataset1.slx (no modifications saved)
here = fileparts(mfilename('fullpath'));
addpath(fullfile(here,'..','SimulnkModel'));
mdl = 'Estimationdataset1';
load_system(mdl);
blks = find_system(mdl,'LookUnderMasks','all','FollowLinks','on','BlockType','ToWorkspace');
for i=1:numel(blks)
    pc = get_param(blks{i},'PortConnectivity');
    src = pc(1).SrcBlock; srcp = pc(1).SrcPort;
    fprintf('%-45s var=%-8s <- %s (port %d)\n', strrep(blks{i},newline,' '), get_param(blks{i},'VariableName'), strrep(getfullname(src),newline,' '), srcp+1);
end
% Multiport switch inputs
ms = find_system(mdl,'SearchDepth',1,'BlockType','MultiPortSwitch');
pc = get_param(ms{1},'PortConnectivity');
for k=1:numel(pc)
    if ~isempty(pc(k).SrcBlock), fprintf('Switch in%d <- %s (port %d)\n',k,strrep(getfullname(pc(k).SrcBlock),newline,' '),pc(k).SrcPort+1); end
    if ~isempty(pc(k).DstBlock), for d=pc(k).DstBlock', fprintf('Switch out -> %s\n',strrep(getfullname(d),newline,' ')); end, end
end
fprintf('Switch params: %s\n', get_param(ms{1},'DataPortOrder'));
% Manual switch & root wiring
for b = find_system(mdl,'SearchDepth',1)'
    if strcmp(b{1},mdl), continue; end
    pc = get_param(b{1},'PortConnectivity');
    srcs = {};
    for k=1:numel(pc), if ~isempty(pc(k).SrcBlock) && pc(k).SrcBlock>0, srcs{end+1}=sprintf('%s:%d',strrep(get_param(pc(k).SrcBlock,'Name'),newline,' '),pc(k).SrcPort+1); end, end
    fprintf('ROOT %-25s <- %s\n', strrep(get_param(b{1},'Name'),newline,' '), strjoin(srcs,', '));
end
fprintf('ManualSwitch setting: %s\n', get_param([mdl '/Manual Switch'],'sw'));
