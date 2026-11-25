std = 'luajit'
unused_args = false
globals = { 'script', 'FRSS_TEST', 'ac', 'physics', 'render', 'ui', 'vec2', 'vec3', 'rgbm', 'bit' }
max_line_length = 130
files['tests/'] = { globals = { 'vec2', 'vec3', 'rgbm', 'bit', 'ac', 'physics', 'render', 'ui', 'script', 'FRSS_TEST' } }
