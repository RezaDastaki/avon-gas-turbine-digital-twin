max(abs(z_dev_cpr(1000:3000)))
mean(z_dev_cpr(1000:3000))
var(z_dev_cpr(1000:3000))

max(abs(z_dev_prss_turb(1000:3000)))
mean(z_dev_prss_turb(1000:3000))
var(z_dev_prss_turb(1000:3000))


max(abs(z_dev_pw_pt(1000:3000)))
mean(z_dev_pw_pt(1000:3000))
var(z_dev_pw_pt(1000:3000))



max(abs(z_dev_temo_comp(1000:3000)))
mean(z_dev_temo_comp(1000:3000))
var(z_dev_temo_comp(1000:3000))



max(abs(z_dev_temp_pt(1000:3000)))
mean(z_dev_temp_pt(1000:3000))
var(z_dev_temp_pt(1000:3000))


max(abs(z_dev_temp_turb(1000:3000)))
mean(z_dev_temp_turb(1000:3000))
var(z_dev_temp_turb(1000:3000))





zzz_adaptiveTh

close all
nv=500
mv=3000
smpv=1

timev=((0:smpv:(mv-nv))/60)'

figure;
subplot(3,1,1); plot(timev,zzz_adaptiveTh(nv:smpv:mv,1:3));
xlabel('time (min.)'); ylabel('CPR')
legend('Variable','Uupper Bound','Lower Bound')
subplot(3,1,2); plot(timev,zzz_adaptiveTh(nv:smpv:mv,4:6));
xlabel('time (min.)'); ylabel('Temp. Comp. (^oC)')
legend('Variable','Uupper Bound','Lower Bound')
subplot(3,1,3); plot(timev,zzz_adaptiveTh(nv:smpv:mv,7:9));
xlabel('time (min.)'); ylabel('Temp. Tur. (^oC)')
legend('Variable','Uupper Bound','Lower Bound')
figure;
subplot(3,1,1); plot(timev,zzz_adaptiveTh(nv:smpv:mv,10:12));
xlabel('time (min.)'); ylabel('Press. Tur. (kPa)')
legend('Variable','Uupper Bound','Lower Bound')
subplot(3,1,2); plot(timev,zzz_adaptiveTh(nv:smpv:mv,13:15));
xlabel('time (min.)'); ylabel('Temp. PT. (^oC)')
legend('Variable','Uupper Bound','Lower Bound')
subplot(3,1,3); plot(timev,zzz_adaptiveTh(nv:smpv:mv,16:18));
xlabel('time (min.)'); ylabel('Gen.Power PT (MW)')
legend('Variable','Uupper Bound','Lower Bound')

