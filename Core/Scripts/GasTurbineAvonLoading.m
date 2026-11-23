clear; clc;
load dataloadGTAvon.mat

n=2200;
m=7000;



GasGen_Speed_SECF210_rpm             =data(n:m,1);                 %SECF_210
Prss_FG_Aftr_MCV_PT204_kPa           =data(n:m,2)*0.068948*100;    %PT_204
Starter_spd_SE202_rpm                =data(n:m,3);                 %SE_202 
Temp_Exhst_EGT_oC                    =data(n:m,4);                 %EGT
PwrTrb_Speed_SECF243_rpm           =data(n:m,5);                 %SECF_243
Prss_FG_Bfr_MCV_PT203_kPa            =data(n:m,6)*100;             %PT_203
ExGasTrb_PID_MV_percent              =data(n:m,7);                  %EGT_PID_MV
GasGen_PID_SP_rpm                 =data(n:m,8);                  %GG_PID_SP   
GasGen_PID_MV_percent                =data(n:m,9);                  %GG_PID_MV  
PwrTrb_PID_SP_rpm                 =data(n:m,10);                 %PT_PID_SP  
PwrTrb_PID_MV_percent                =data(n:m,11);                 %PT_PID_MV   
PwrTrb_210_CDP                   =data(n:m,12);                   %PT_210_CDP   
St1_Controller_PV            =data(n:m,13);   %St1_Controller_PV
St1_Plotter_FLOW_OUT_m3ps         =data(n:m,14);   %St1_Plotter_FLOW_OUT
St1_Plotter_DP_OUT           =data(n:m,15);   %St1_Plotter_DP_OUT
PrpnPump_Inlet_Flow_FT114_m3ps                       =data(n:m,16); %FT_114 
PrpnPump_Outlet_Flow_FT115_m3ps                       =data(n:m,17);   %FT_115
PDT_139                      =data(n:m,18);   %PDT_139
PDT_140                      =data(n:m,19);   %PDT_140 
St2_Controller_PV            =data(n:m,20);   %St2_Controller_PV
St2_Controller_MV            =data(n:m,21);   %St2_Controller_MV  
St2_Plotter_FLOW_OUT_m3ps         =data(n:m,22);   %St2_Plotter_FLOW_OUT  
St2_Plotter_DP_OUT           =data(n:m,23);   %St2_Plotter_DP_OUT  
Temp_AirIntake_TT211AirIntake_oC       =data(n:m,24);             %TT_211_AirIntake
Temp_Seal_TT210SEALTEMP_oC             =data(n:m,25);   	      %TT_210_SEAL_TEMP



time(1:m-n+1,1)=(0:m-n);

clear n m data; clc;
display('Gas Turbine Avon Loading Condition')
who;