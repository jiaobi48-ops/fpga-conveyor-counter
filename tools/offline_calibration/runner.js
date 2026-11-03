/* CLI bridge. Input contains base64 RGB/masks already decoded by run_model.py. */
'use strict';
const fs=require('node:fs'),M=require('./model.js');
try{
  const raw=fs.readFileSync(0,'utf8');if(raw.length>400000000)throw Error('input_too_large');
  const x=JSON.parse(raw);
  for(const key of ['trainEmpty','trainObjects','validationEmpty','validationObjects','blockedDark','blockedWarm'])if(x[key])x[key]=x[key].map(f=>({...f,rgb:new Uint8Array(Buffer.from(f.rgb_base64,'base64')),...(f.mask_base64?{mask:new Uint8Array(Buffer.from(f.mask_base64,'base64'))}:{})}));
  process.stdout.write(JSON.stringify(M.propose(x),null,2)+'\n');
}catch(e){process.stderr.write(String(e.message)+'\n');process.exitCode=1;}
