-- vim: ft=lua ts=2 sw=2
-- Omit next line in actual module clients; it's only to support development of the module itself
package.path = "../src/?.lua;" .. package.path

pcall(require, "luacov")

print("------------------------------------")
print("Lua version: " .. (jit and jit.version or _VERSION))
print("------------------------------------")
print("")

local HAS_RUNNER = not not lunit
local lunitx
if not HAS_RUNNER then
	lunitx = require"lunitx"
else
	lunitx = require"lunit"
end
local TEST_CASE = lunitx.TEST_CASE

local LUA_VER = _VERSION
local unpack, pow, bit32 = unpack, math.pow, bit32

local _ENV = TEST_CASE"html"

local htmlparser = require("htmlparser")

function test_void()
	local tree = htmlparser.parse([[
		<p>
			<br>
			<br/>
			<br >
			<br />
		</p>
		<br>
		<br/>
		<br >
		<br />
	]])
	assert_equal(5, #tree.nodes, "top level")
	for _,n in ipairs(tree.nodes) do
		if n.name == "p" then
			assert_equal(4, #n.nodes, "deeper level")
		else
			assert_equal("br", n.name, "name")
			assert_equal("", n:getcontent(), "content")
		end
	end
end

function test_id()
	local tree = htmlparser.parse([[
		<n id="4711">
			<m id="1174"></m>
		</n>
	]])
	assert_equal(1, #tree.nodes, "top level")
	assert_equal("n", tree("#4711")[1].name, "#4711")
	assert_equal("m", tree("#1174")[1].name, "#1174")
end

function test_class()
	local tree = htmlparser.parse([[
		<n class="one">
			<n class="two">
				<n class="three"></n>
			</n>
		</n>
		<n class="two three"></n>
		<n ssalc="four"></n>
	]])
	assert_equal(3, #tree.nodes, "top level")
	assert_equal(1, #tree(".one"), ".one")
	assert_equal(2, #tree(".two"), ".two")
	assert_equal(2, #tree(".three"), ".three")
	assert_equal(1, #tree(".two.three"), ".two.three")
	assert_equal(0, #tree(".four"), ".four")
end

function test_attr()
	local tree = htmlparser.parse([[
		<n a1 a2= a3='' a4=""
			a5='a"5"' a6="a'6'" a7='#.[] :()' a8='|*+-=?$^%&/'
			a9=a9
		a10></n>
	]])
	assert_equal(1, #tree.nodes, "top level")
	assert(tree("[a1]")[1], "a1")
	assert(tree("[a2]")[1], "a2")
	assert(tree("[a3]")[1], "a3")
	assert(tree("[a4]")[1], "a4")
	assert(tree("[a5]")[1], "a5")
	assert(tree("[a6]")[1], "a6")
	assert(tree("[a7]")[1], "a7")
	assert(tree("[a8]")[1], "a8")
	assert(tree("[a9]")[1], "a9")
	assert(tree("[a10]")[1], "a10")
end

function test_attr_equal()
	local tree = htmlparser.parse([[
		<n a1 a2= a3='' a4=""
			a5='a"5"' a6="a'6'" a7='#.[]:()' a8='|*+-=?$^%&/'
			a9=a9
		a10></n>
	]])
	assert_equal(1, #tree.nodes, "top level")
	assert(tree("[a1='']")[1], "a1=''")
	assert(tree("[a2='']")[1], "a2=''")
	assert(tree("[a3='']")[1], "a3=''")
	assert(tree("[a4='']")[1], "a4=''")
	assert(tree("[a5='a\"5\"']")[1], "a5='a\"5\"'")
	assert(tree("[a6=\"a'6'\"]")[1], "a6=\"a'6'\"")
	assert(tree("[a7='#.[]:()']")[1], "a7='#.[]:()'")
	assert(tree("[a8='|*+-=?$^%&/']")[1], "a8='|*+-=?$^%&/'")
	assert(tree("[a9='a9']")[1], "a9='a9'")
	assert(tree("[a10='']")[1], "a10=''")
	assert(tree("[a10=]")[1], "a10=")
end

function test_attr_notequal()
	local tree = htmlparser.parse([[
		<n a1="a1"></n>
		<n a1="a2"></n>
		<n a1></n>
		<n></n>
	]])
	assert_equal(4, #tree.nodes, "top level")
	assert_equal(3, #tree("[a1!='a1']"), "a1!='a1'")
	assert_equal(4, #tree("[a1!='b1']"), "a1!='b1'")
	assert_equal(3, #tree("[a1!='']"), "a1!=''")
	assert_equal(3, #tree("[a1!=]"), "a1!=")
end

function test_attr_prefix_start_end()
	local tree = htmlparser.parse([[
		<n a1="en-gb"></n>
		<n a1="en-us"></n>
		<n a1="en"></n>
		<n a1="enen"></n>
		<n></n>
	]])
	assert_equal(5, #tree.nodes, "top level")
	assert_equal(3, #tree("[a1|='en']"), "a1|='en'")
	assert_equal(4, #tree("[a1^='en']"), "a1^='en'")
	assert_equal(2, #tree("[a1$='en']"), "a1$='en'")
end

function test_attr_word()
	local tree = htmlparser.parse([[
		<n a1="one two three"></n>
		<n a1="three four five"></n>
		<n a1></n>
		<n></n>
	]])
	assert_equal(4, #tree.nodes, "top level")
	assert_equal(1, #tree("[a1~='two']"), "a1~='two'")
	assert_equal(2, #tree("[a1~='three']"), "a1~='three'")
	assert_equal(1, #tree("[a1~='four']"), "a1~='four'")
end

function test_attr_contains()
	local tree = htmlparser.parse([[
		<n a1="one"></n>
		<n a1="one two three"></n>
		<n a1="three four five"></n>
		<n a1=""></n>
		<n a1></n>
		<n></n>
	]])
	assert_equal(6, #tree.nodes, "top level")
	assert_equal(2, #tree("[a1*='one']"), "a1*='one'")
	assert_equal(2, #tree("[a1*='t']"), "a1*='t'")
	assert_equal(1, #tree("[a1*='f']"), "a1*='f'")
	assert_equal(5, #tree("[a1*='']"), "a1*=''")
	assert_equal(5, #tree("[a1*=]"), "a1*=")
end

function test_descendants()
	local tree = htmlparser.parse([[
		<parent>1
			<child>1</child>
			<child>2
				<child>3</child>
			</child>
			<arbitrary>
				<child>4</child>
			</arbitrary>
		</parent>
		<parent>2
			<child>5</child>
			<child>6
				<child>7</child>
			</child>
			<arbitrary>
				<child>8</child>
			</arbitrary>
		</parent>
		<arbitrary>
			<child>not</child>
		</arbitrary>
	]])
	assert_equal(8, #tree("parent child"), 'parent child')
end

function test_children()
	local tree = htmlparser.parse([[
		<parent>1
			<child>1</child>
			<child>2
				<child>not</child>
			</child>
			<arbitrary>
				<child>not</child>
			</arbitrary>
		</parent>
		<parent>2
			<child>3</child>
			<child>4
				<child>not</child>
			</child>
			<arbitrary>
				<child>not</child>
			</arbitrary>
		</parent>
		<arbitrary>
			<child>not</child>
		</arbitrary>
	]])
	assert_equal(4, #tree("parent > child"), 'parent > child')
end

function test_not()
	local tree = htmlparser.parse([[
		<n a1="1" a2>
			<m a1="1"></m>
		</n>
		<n a2></n>
	]])
	assert_equal(2, #tree.nodes, "top level")
	assert_equal(1, #tree(":not([a1=1])"), ":not([a1=1])")
	assert_equal(1, #tree(":not([a2])"), ":not([a2])")
	assert_equal(1, #tree(":not(n)"), ":not(n)")
	assert_equal(2, #tree(":not(m)"), ":not(m)")
end

function test_combine()
	local tree = htmlparser.parse([[
		<e class="a b c" a="2-two">
			<n b="123"></n>
			<n id="123" b="321">
				<n b="222"></n>
				<n class="c" b="345"></n>
			</n>
		</e>
		<n b="222"></n>
	]])
	assert_equal(2, #tree.nodes, "top level")
	assert_equal(2, #tree("e.c:not([a|='1']) > n[b*='2']"), "e.c:not([a|='1']) > n[b*='2']")
	assert_equal(3, #tree("e.c:not([a|='1'])   n[b*='2']"), "e.c:not([a|='1'])   n[b*='2']")
	assert_equal(1, #tree("#123 .c[b]"), "#123 .c[b]")
end

function test_order()
  local tree = htmlparser.parse([[
    <1>
      <n>1</n>
      <2>
        <n>2</n>
        <n>3</n>
        <3>
          <n>4</n>
          <n>5</n>
          <n>6</n>
          <4>
            <n>7</n>
            <n>8</n>
            <n>9</n>
            <n>10</n>
          </4>
        </3>
      </2>
    </1>
  ]])
  assert_equal(1, #tree.nodes, "top level")
  local n = tree("n")
  assert_equal(10, #n, "n")
  for i,v in pairs(n) do
    assert_equal(i, tonumber(v:getcontent()), "n order")
  end
  local notn = tree(":not(n)")
  assert_equal(4, #notn, "notn")
  for i,v in pairs(notn) do
    assert_equal(i, tonumber(v.name), "notn order")
  end
end

function test_tagnames_with_hyphens()
	local tree = htmlparser.parse([[
		<tag-name id="9999">
			<m id="10000"></m>
		</tag-name>
	]])
	assert_equal(1, #tree.nodes, "top level")
	assert_equal("tag-name", tree("#9999")[1].name, "#9999")
	assert_equal("m", tree("#10000")[1].name, "#10000")
end

function test_loop_limit()
	local tree = htmlparser.parse([[
		<a id='a >b'>moo</a>
		<a id='c> d'>moo</a>
		<a id='e > f'>moo</a>
		<a id="g >h">moo</a>
		<a id="i> j">moo</a>
		<a id="k > l">moo</a>
		<a id='1>2'>moo</a>
		<b id='foo<bar'>moo</b>
		<img <%tpl%> foo=bar></img>
		<img <%tpl%> />
		<img <%tpl%>></img>
		<img <%tpl%>/>
		<i <=moo=>>k</i>
		<s <-foo->>o</s>
		<div <*bar*>></div>
		<a id="unclosed>Element"> with unclosed attribute</a>
		<div data-pic="aa<%=image_url%>bb" ></div>
	]]) -- issue#42
	assert(#tree.nodes==17)
end
