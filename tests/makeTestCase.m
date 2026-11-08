function C = makeTestCase()
%MAKETESTCASE 单元测试用的小算例：冒烟算例拓扑，1 个合成气象年（训练/验证/测试共用），自助法 20 次，不并行。

p = params_default('smoke');
p.weather.Y = 1;
p.weather.train = 1;
p.weather.val = 1;
p.weather.test = 1;
p.stats.bootB = 20;
p.data.useParfor = false;
C = buildCase(p);
end
