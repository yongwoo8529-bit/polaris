import"./modulepreload-polyfill-B5Qt9EMX.js";/* empty css              */import{createClient as b}from"https://cdn.jsdelivr.net/npm/@supabase/supabase-js/+esm";const f="https://ixouybhxjiijtpyhwhjv.supabase.co",p="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml4b3V5Ymh4amlpanRweWh3aGp2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU1NTI0NDYsImV4cCI6MjA5MTEyODQ0Nn0.TTOQNdFFQNW5OKzb4DkKlWuCL8cSw4zP9DmfpojU47o",l=[{id:1,name:"탐구의 은하",emoji:"🟣",color:"#a55eea"},{id:2,name:"질서의 은하",emoji:"🔵",color:"#45aaf2"},{id:3,name:"온기의 은하",emoji:"🟠",color:"#fd9644"},{id:4,name:"울림의 은하",emoji:"🟡",color:"#fed330"},{id:5,name:"울타리의 은하",emoji:"🟢",color:"#26de81"},{id:6,name:"프리즘의 은하",emoji:"🌈",color:"#ffffff"}],j=b(f,p);let m=[],t=1;async function I(){const{data:e,error:o}=await j.from("jobs").select("name, galaxy_id").order("galaxy_id");!o&&e&&(m=e),r(),d(t),document.getElementById("jobs-loading").style.display="none"}function r(){const e=document.getElementById("galaxy-tabs");e.innerHTML=l.map(o=>`
        <button class="galaxy-tab ${o.id===t?"active":""}"
            style="--tab-color:${o.color}"
            onclick="switchTab(${o.id})">
            ${o.emoji} ${o.name}
        </button>
    `).join("")}function d(e){const o=l.find(n=>n.id===e),a=m.filter(n=>n.galaxy_id===e),i=document.getElementById("jobs-grid"),c=document.getElementById("jobs-count");if(a.length===0){i.innerHTML='<div class="empty-state">직업 정보를 불러오는 중...</div>',c.textContent="";return}c.textContent=`${(o==null?void 0:o.name)||""} · ${a.length}개 직업`,i.innerHTML=a.map(n=>`
        <a class="job-badge" href="job.html?job=${encodeURIComponent(n.name)}"
            style="border-color:${(o==null?void 0:o.color)||"#fff"}33">
            ${n.name}<span class="arrow">›</span>
        </a>
    `).join("")}window.switchTab=function(e){t=e,r(),d(e),history.replaceState(null,"",`#galaxy-${e}`)};const s=location.hash.match(/galaxy-(\d)/);s&&(t=parseInt(s[1]));I();
