var nav=document.getElementById('nav');addEventListener('scroll',function(){nav.classList.toggle('s',scrollY>30)},{passive:true});
var io=new IntersectionObserver(function(es){es.forEach(function(e){if(e.isIntersecting){e.target.classList.add('in');io.unobserve(e.target)}})},{threshold:.12});
document.querySelectorAll('.rv').forEach(function(el,i){el.style.transitionDelay=(i%3)*.1+'s';io.observe(el)});
var co=new IntersectionObserver(function(es){es.forEach(function(e){if(!e.isIntersecting)return;var el=e.target,to=+el.dataset.to,t0=performance.now();(function f(t){var p=Math.min((t-t0)/1500,1);el.textContent=Math.round(to*(1-Math.pow(1-p,3))).toLocaleString('en-US');if(p<1)requestAnimationFrame(f)})(t0);co.unobserve(el)})},{threshold:.5});
document.querySelectorAll('.cn').forEach(function(el){co.observe(el)});
var q=document.getElementById('qr'),on=[0,1,2,7,8,9,14,4,5,6,11,13,20,21,23,28,30,35,36,37,42,44,46,48,26,16,18,33];
for(var i=0;i<49;i++){var c=document.createElement('i');var r=Math.floor(i/7),k=i%7,fin=(r<3&&(k<3||k>3))||(r>3&&k<3&&r>3);if(!(on.indexOf(i)>-1||fin))c.className='o';q.appendChild(c)}
var D=[['phone','تطبيق الطالب','الواجهة التي يرى منها الطالب كل شيء: اشتراكه، رحلته، ومحطاته.',['إنشاء الحساب واختيار الجامعة','الاشتراك الإلكتروني ورفع إيصال الدفع','QR خاص وإشعارات لحظية']],
['shield','تطبيق المشرف','أداة التشغيل اليومية: يرى رحلاته، يتحقق من الطلاب، ويدير الذهاب والعودة.',['ملخص اليوم والرحلات الحالية','محطات الذهاب والعودة بوضوح','QR للتحقق من بيانات الطالب واشتراكه']],
['mon','لوحة تحكم الشركة','Web SaaS كامل تدير منه الشركة عملياتها كلها من المتصفح.',['الرحلات المباشرة والخطوط والمحطات','الطلاب والاشتراكات والإيصالات','التحليلات والإشعارات والشكاوى']],
['globe','لوحة تحكم باصك','مركز قيادة المنصة لمالكها: كل الشركات والتشغيل والفوترة في مكان واحد.',['جميع الشركات والاشتراكات والخطط','الاستخدام والتحليلات العامة','الفوترة وسجلات التدقيق']]];
var det=document.getElementById('det');
function show(i){var d=D[i];det.innerHTML='<span class="ic"><svg><use href="#'+d[0]+'"/></svg></span><h3>'+d[1]+'</h3><p>'+d[2]+'</p><ul>'+d[3].map(function(x){return'<li>'+x+'</li>'}).join('')+'</ul>';det.classList.remove('fd');void det.offsetWidth;det.classList.add('fd')}
show(0);
document.querySelectorAll('.tb').forEach(function(b){b.addEventListener('click',function(){document.querySelectorAll('.tb').forEach(function(x){x.classList.remove('on')});b.classList.add('on');show(+b.dataset.i)})});

// Language toggle for the privacy section (Arabic default; one shown at a time).
(function(){var box=document.getElementById('privacy');if(!box)return;var ar=document.getElementById('ar'),en=document.getElementById('en');var btns=box.querySelectorAll('.pvl');function set(l){if(ar)ar.hidden=l!=='ar';if(en)en.hidden=l!=='en';btns.forEach(function(b){b.classList.toggle('on',b.dataset.lang===l)})}btns.forEach(function(b){b.addEventListener('click',function(){set(b.dataset.lang)})});set('ar')})();
