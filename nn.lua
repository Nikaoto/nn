local nn = {
   _VERSION = "nn.lua 0.0.1",
   _URL     = "http://github.com/Nikaoto/nn.lua",
   _DESCRIPTION = "small neural network library",
   _LICENSE = [[ BSD3 ]]
}

-- For debugging
local k=false
local function printk(msg)
   if k then print(msg) end
end

-- Defaults
local def = {
   act_fns = {},
   d_act_fns = {},
   learning_rate = 0.001,
   epochs = 1000,
   training_log_freq = 0.01,
   weight_min = -5,
   weight_max = 5,
   bias_min = -5,
   bias_max = 5,
   shuffle_training_data = false,
}

local function sq(x) return x*x end

local function lerp(a, b, p) return a + (b-a)*p end

local function rand_lerp(min, max)
   return lerp(min, max, math.random(0, 1000) / 1000)
end

local function map(arr, fn)
    local new_arr = {}    
    for i, _ in ipairs(arr) do
        new_arr[i] = fn(arr[i], i)
    end
    return new_arr
end

local function shuffle_array(arr)
   for i=#arr, 1, -1 do
      local j = math.random(1, i)
      arr[j], arr[i] = arr[i], arr[j]
   end
end

-- Make an array of 'nmemb' elements and set all of them to 'value'
local function make_array(nmemb, value)
   local arr = {}
   for i=1, nmemb do table.insert(arr, value) end
   return arr
end

-- Calculate the error for a single example
local function calc_err(actual, desired)
   return sq(actual - desired)
end

-- Calculate the derivative of the error function
local function calc_d_err(actual, desired)
   return 2 * (actual - desired)
end

-- Calculate the sum of all errors
local function calc_total_err(actual_arr, desired_arr)
   local loss = 0
   for i, _ in ipairs(actual_arr) do
      loss = loss + calc_err(actual_arr[i], desired_arr[i])
   end
   return loss
end

-- Sigmoid activation function and its derivative
function nn.sigmoid(a) return 1 / (1 + math.exp(-a)) end
-- 'sa' here is assumed to already be the sigmoid of the neuron activation
function nn.d_sigmoid(sa) return sa * (1 - sa) end

-- ReLU activation function and its derivative
function nn.relu(a) return a > 0 and a or 0 end
function nn.d_relu(a) return a > 0 and 1 or 0 end

-- Returns a table that represents a neural network
function nn.new_neural_net(opts)
   if not opts then opts = {} end

   local neuron_counts = opts.neuron_counts
   local act_fns       = opts.act_fns    or def.act_fns
   local d_act_fns     = opts.d_act_fns  or def.d_act_fns
   local weight_min    = opts.weight_min or def.weight_min
   local weight_max    = opts.weight_max or def.weight_max
   local bias_min      = opts.bias_min   or def.bias_min
   local bias_max      = opts.bias_max   or def.bias_max
   local weights       = opts.weights
   local biases        = opts.biases

   if not neuron_counts then
      error("nn.new_neural_net(): no opts.neuron_counts given")
   end

   local rand_weight = function()
      return rand_lerp(weight_min, weight_max)
   end

   local rand_bias = function()
      return rand_lerp(bias_min, bias_max)
   end

   local net = {
      act_fns = act_fns,
      d_act_fns = d_act_fns,
      neurons = map(neuron_counts, make_array),
   }

   --[[ NOTE:
      Weights are defined left-to-right.
      Meaning, in a net like this:
      +-----------------+
      | in  hidden  out |
      | --  ------  --- |
      |      c          |
      | a    d  g    i  |
      | b    e  h    k  |
      |      f          |
      +-----------------+
      The weights are defined as:
      {
        { ac, ad, ae, af, bc, bd, be, bf },
        { cg, ch, dh, dh, eg, eh, fg, fh },
        { gi, gk, hi, hk }
      }

      The reason behind this is that it becomes easier to index
      the weights relative to the neuron indices.
   ]]--

   -- Create random weights if none given
   if not weights then
      weights = {}
      for li=1, #net.neurons-1 do
         weights[li] = {}
         for i=1, #net.neurons[li] * #net.neurons[li+1] do
            table.insert(weights[li], rand_weight())
         end
      end
   end
   net.weights = weights

   -- Create random biases if none given
   if not biases then
      biases = {
         -- Input and output layers have no biases
         [1] = nil,
         [#net.neurons] = nil,
      }
      for li=2, #net.neurons-1 do
         biases[li] = map(net.neurons[li], rand_bias)
      end
   end
   net.biases = biases

   return net
end

function nn.insert_inputs(net, inputs)
   for i, _ in ipairs(net.neurons[1]) do
      net.neurons[1][i] = inputs[i]
   end
end

-- Feeds inputs forward and returns output layer
function nn.feedforward(net, opts)
   if not opts then opts = {} end
   if opts.inputs then nn.insert_inputs(net, opts.inputs) end

   for li=2, #net.neurons, 1 do
      for ni, _ in ipairs(net.neurons[li]) do
         -- Dot product of previous layer's neurons and weights
         local dp = 0
         for plni, _ in ipairs(net.neurons[li-1]) do
            -- 'plni' stands for 'previous layer neuron index'
            local wi = ni + (plni-1) * #net.neurons[li]
            local weight = net.weights[li-1][wi]
            local prev_activation = net.neurons[li-1][plni]
            dp = dp + prev_activation * weight
         end

         -- Add bias
         local act = dp + (net.biases[li] and net.biases[li][ni] or 0)

         -- Apply activation function
         if net.act_fns and net.act_fns[li-1] then
            net.neurons[li][ni] = net.act_fns[li-1](act)
         else
            net.neurons[li][ni] = act
         end
      end
   end

   return net.neurons[#net.neurons]
end

-- Expects 'training_data' to be shaped like:
-- {
--    { inputs = {...}, outputs = {...} },
--    { inputs = {...}, outputs = {...} },
--    ...
-- }
function nn.train(net, training_data, opts)
   if not opts then opts = {} end

   local learning_rate   = opts.learning_rate or def.learning_rate
   local epochs          = opts.epochs        or def.epochs
   local shuf            = opts.shuf          or def.shuffle_training_data
   local log_freq        = opts.log_freq      or def.training_log_freq
   local log_every       = 1 / log_freq

   for iter=1, epochs do
      if shuf then shuffle_array(training_data) end

      local avg_loss = 0
      for _, data in ipairs(training_data) do
         local out = nn.feedforward(net, { inputs = data.inputs })

         -- Update average loss
         local loss = calc_total_err(out, data.outputs)
         avg_loss = avg_loss + loss / #training_data

         -- Do backpropagation
         local nudges = nn.backprop(net, data.outputs, learning_rate)
         nn.apply_nudges(net, nudges)
      end

      -- Log status
      if iter % log_every == 0 or iter == 1 then
         print(("epoch = %i, avg_loss = %g"):format(iter, avg_loss))
      end
   end
end

-- Does backpropagation for a single training example.
-- Returns a list of nudges for the weights and the biases.
function nn.backprop(net, out, rate)
   local wnudges = {}
   local bnudges = {}

   local curr_der -- for using the stored derivatives
   local next_der -- for storing derivatives for propagation

   -- Calc pd_error / pd_output
   curr_der = map(net.neurons[#net.neurons], function(o, i)
       return calc_d_err(o, out[i])
   end)
   next_der = {}

   -- Iterate backwards from output layer
   for li=#net.weights, 1, -1 do
      wnudges[li] = {}
      bnudges[li] = {}
      for wi, _ in ipairs(net.weights[li]) do
         -- Neuron at index 'ni1' feeds into the neuron at index 'ni2'
         -- using the current weight 'w'.
         local ni1 = 1 + math.floor((wi-1) / #net.neurons[li+1])
         local ni2 = 1 + (wi-1) % #net.neurons[li+1]

         -- pd_activation / pd_neuron
         local a = net.d_act_fns[li] and
                   net.d_act_fns[li](net.neurons[li+1][ni2]) or 1

         -- Final nudge for this weight
         wnudges[li][wi] = -1 * rate * curr_der[ni2] * net.neurons[li][ni1] * a

         printk(("ni1=%i, ni2=%i, li=%i, wi=%i, e=%g, a=%g, grad=%g")
               :format(ni1, ni2, li, wi, curr_der[ni2], a, wnudges[li][wi]))

         -- Propagate derivatives to the layers that follow
         next_der[ni1] = (next_der[ni1] or 0) +
                         curr_der[ni2] * a * net.weights[li][wi]

         if net.biases[li] then
            bnudges[li][ni1] = -1 * rate * curr_der[ni2] * a *
                  (net.d_act_fns[li-1] and
                   net.d_act_fns[li-1](net.neurons[li][ni1]) or 1)
         end
      end

      -- Shift the derivative buffers
      curr_der = next_der
      next_der = {}
   end

   return {
      weights = wnudges,
      biases = bnudges,
   }
end

function nn.apply_nudges(net, nudges)
   local wnudges = nudges.weights
   local bnudges = nudges.biases

   for li, _ in ipairs(net.weights) do
      for wi, _ in ipairs(net.weights[li]) do
         net.weights[li][wi] = net.weights[li][wi] + wnudges[li][wi]
      end
   end

   for li, _ in pairs(net.biases) do
      for bi, _ in ipairs(net.biases[li]) do
         net.biases[li][bi] = net.biases[li][bi] + bnudges[li][bi]
      end
   end
end

return nn