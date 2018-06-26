require("rttlib")
require "rttros"
tc=rtt.getTC()

--import common functions like startHook(), stopHook() and cleanupHook()
metacontroller_path = rttros.find_rospack("agni_rtt_services")
package.path = metacontroller_path..'/scripts'..'/?.lua;' .. package.path 
require("meta-component_common")

--wrapper interface definition (should not be changed)
iface_spec = {
   ports={},
   properties={
      { name='namespace', datatype='string', desc="namespace as prefix" },
      { name='in_portmap', datatype='agni_rtt_services/ControlIOMap', desc="input port mapping" },
      { name='out_portmap', datatype='agni_rtt_services/ControlIOMap', desc="output port mapping" },
      { name='resources', datatype='strings', desc="joints controlled by this controller" },
      { name='controller_name', datatype='string', desc="controller name" },
   }
}
 
-- this create the interface
iface=rttlib.create_if(iface_spec)

-- defines the configureHook of the wrapper
function configureHook()
  -- find the deployer
  local d=tc:getPeer("Deployer")
  tcName=tc:getName()

  if tcName=="lua" then
    d=tc:getPeer("Deployer")
  elseif tcName=="Deployer" then
    d=tc
  end

  -- import the all the required libraries and typekits of your inner components
  d:import("rtt_rosnode")
  d:import("rtt_roscomm")
  d:import("rtt_std_msgs") --for gazebo_attach
  d:import("rtt_sensor_msgs")
  d:import("rtt_diagnostic_msgs")
  d:import("s_log_saver")
  d:import("agni_rtt_services")
  d:import("tactile_servoing") 
  d:import("rtt_trajectory_msgs") --for the desired trajectory
  d:import("rtt_std_srvs")
  d:import("rtt_geometry_msgs")
  d:import("rtt_reba_srvs")
  d:import("rtt_tactile_msgs")
  d:import("gazebo_attach_controller")

  -- this create the interface
  iface=rttlib.create_if(iface_spec)
  
  -- retrieve the properties from the interface parameters
  namespace = iface.props.namespace:get()
  -- advertize the type of controller you set (useful for controller_manager)
--   controller_name = tc:getProperty("controller_name")
  resources = tc:getProperty("resources")
  
  -- process user properties
  -- user_property = iface.props.user_property:get() -- ##CHANGE ME##

  -- initialize the port maps
  local in_portmap={}
  local out_portmap={}
  
  
  -- deploy your components that are part of the wrapper
  comp2name = namespace.."Log" -- ##CHANGE ME##
  d:loadComponent(comp2name, "SLogSaver") -- ##CHANGE ME##
  d:setActivity(comp2name, 0, 20, rtt.globals.ORO_SCHED_RT) -- ##CHANGE ME##
  comp2 = d:getPeer(comp2name) -- ##CHANGE ME##
  comp2:getProperty("ID"):set(0)
  comp2:configure() -- ##CHANGE ME##
  -- add comp2name to the wrapper component peers
  d:addPeer(tcName, comp2name) -- ##CHANGE ME##
  
    comp3name = namespace.."GAttach" -- ##CHANGE ME##
  d:loadComponent(comp3name, "GazeboAttachController")
  d:setActivity(comp3name, 0.1, 10, rtt.globals.ORO_SCHED_RT)
  comp3 = d:getPeer(comp3name)
  comp3:getProperty("ref_model_name"):set("l_kukaL_schunk_hand_left")
  comp3:getProperty("ref_link_name"):set("la_arm_7_link")
  comp3:getProperty("tgt_model_name"):set("tactile_tool")
  comp3:getProperty("tgt_link_name"):set("la_tactile_tool")
  comp3:configure()
  d:addPeer(tcName, comp3name) -- ##CHANGE ME##
  
    -- deploy your components that are part of the wrapper
  comp1name = namespace.."TSTest" -- ##CHANGE ME##
  d:loadComponent(comp1name, "TactileServoing") -- ##CHANGE ME##
  d:setActivity(comp1name, 0.004, 60, rtt.globals.ORO_SCHED_RT) -- ##CHANGE ME##
  comp1 = d:getPeer(comp1name) -- ##CHANGE ME##
  comp1:getProperty("robot_prefix"):set(namespace)
  d:addPeer(comp1name, comp3name) -- ##CHANGE ME##
  d:addPeer(tcName, comp1name)
  comp1:configure() -- ##CHANGE ME##
  -- add comp1name to the wrapper component peers
  
  
  
  -- advertize ports for the meta-component depending on the type using generic names
  -- among CMDJNTPOS|VEL|EFF, CURJNTPOS|VEL|EFF, CMDJNT, CURJNT, LOG, ...
  -- register ports for the compound controller
  register_port(in_portmap, 'LOG', comp2name..".Log")
  register_port(out_portmap, 'CMDJNT', comp1name..".DesiredJointRA")
  register_port(in_portmap, 'CURJNT', comp1name..".RealJointRA")
--   register_port(in_portmap, 'Int32', comp1name..".ControllerTypeRA")
  
  -- store the mapping in the properties
  storeMapping("in_portmap",in_portmap)
  storeMapping("out_portmap",out_portmap)
  
  -- If your meta-component is a controller, set the resource to match the controlled joints
  --resources:get():resize(7) -- ##CHANGE ME##
--   -- fill the resource
--   for i=0,6,1 do  -- ##CHANGE ME##
--     resources[i] = namespace.."_my_"..i.."_joint" -- ##CHANGE ME##
--   end 


  -- internal connection
--   d:connect(comp1name..".DesiredJointRA", comp2name..".Log", rtt.Variable("ConnPolicy")) -- ##CHANGE ME##
  -- ROS in out
  local ros=rtt.provides("ros")
--   d:stream(comp1name..".MyrmexRA",ros:topic("/tactile_contact_states/rh_myrmex"))
d:stream(comp1name..".MyrmexRA",ros:topic("/right/contacts/rh_myrmex"))
  
  d:stream(comp3name..".Attach", ros:topic("/gazebo_attach"))
  d:stream(comp3name..".Attached", ros:topic("/gazebo_attached"))
  
  
  comp1:loadService("rosservice")
  comp1:provides("rosservice"):connect(namespace.."goHome_servicecall", "/"..namespace.."/goHome_servicecall", "std_srvs/Empty")
  comp1:provides("rosservice"):connect(namespace.."tactileServoing_servicecall", "/"..namespace.."/tactileServoing_servicecall", "std_srvs/Empty")
  comp1:provides("rosservice"):connect(namespace.."setGrasp_servicecall", "/"..namespace.."/setGrasp_servicecall", "reba_srvs/SetPose")


  print(namespace.."Wrapper is configured")
  return true
end
