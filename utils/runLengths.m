function [len, startIdx] = runLengths(mask)
%RUNLENGTHS 逻辑序列中连续为真的段长度与起点（用于低风光、富余事件的持续天数统计）。

mask = logical(mask(:))';
d = diff([false, mask, false]);
startIdx = find(d == 1);
stopIdx = find(d == -1) - 1;
len = stopIdx - startIdx + 1;
end
