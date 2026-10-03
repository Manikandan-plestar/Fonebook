const fs = require('fs');
const src = fs.readFileSync('FoneBook.js', 'utf8');
const lines = src.split('\n');
const routes = [];
lines.forEach((line, i) => {
  const m = line.match(/app\.(get|post|delete|put|all)\s*\(\s*(?:\[([^\]]+)\]|['"`]([^'"`]+))/);
  if (m) {
    const method = m[1].toUpperCase();
    const paths = m[2]
      ? m[2].split(',').map(s => s.trim().replace(/['"`]/g, ''))
      : [m[3]];
    paths.forEach(p => routes.push({ method, path: p, line: i + 1 }));
  }
});
console.log(JSON.stringify(routes, null, 2));
