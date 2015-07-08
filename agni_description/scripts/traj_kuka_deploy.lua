require "rttlib"
require "rttros"

-- get local path and add to package path to find our local scripts
local pathOfThisFile =debug.getinfo(1,"S").source:match[[^@?(.*[\/])[^\/]-$]]
if pathOfThisFile then
  package.path = pathOfThisFile..'/?.lua;' .. package.path 
end
-- agni functionalities (wait for peer, etc)
require "agni_tools"
-- motion manager include
dofile(pathOfThisFile.."/trajectory_controller_deploy.lua")

tc=rtt.getTC()
tcName=tc:getName()
print (tcName)
if tcName=="lua" then
  d=tc:getPeer("Deployer")
elseif tcName=="Deployer" then
  d=tc
end

-- wait for motion manager to appear
found_traj_controller=wait_for("JntTrajAction",5)
-- wait for kuka to appear
found_rakuka_controller=wait_for("rakuka_controller",2)

if (found_traj_controller and found_rakuka_controller) then

  rakuka_controller = d:getPeer("rakuka_controller")
  -- add controller services -- 
  d:loadService("rakuka_controller","controllerService")
  -- connect the controller wrapper and the motion manager (this should stop the controller and restart it)
  print("rakuka connecting to JntTrajAction")
  
  rakuka_controller:provides("controllerService"):connectIn("FILJNTPOS","JntTrajGen.JointPositionVelocityCommand")
  rakuka_controller:provides("controllerService"):connectOut("JNTPOS","JntTrajAction.JointPosition")
   rakuka_controller:provides("controllerService"):connectOut("JNTPOS","JntTrajGen.JointPosition")
  
end




