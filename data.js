// DATA CONFIGURATION: Chris can replace this demo data with API/database results.
// The hourly percentages below come from the team's earlier Python analysis.
const PARKSMART_HOURLY = [
  {hour:7, available:79.09}, {hour:8, available:74.63},
  {hour:9, available:62.84}, {hour:10, available:53.38},
  {hour:11, available:45.35}, {hour:12, available:40.95},
  {hour:13, available:39.44}, {hour:14, available:39.28},
  {hour:15, available:43.84}, {hour:16, available:49.83}
];
// DEMO ONLY: Garage codes, capacities, and percentages below are illustrative.
// Do not treat them as verified real-world garage statistics.
const PARKSMART_GARAGES = [
  {id:'DEMO-01',name:'Central Station Garage',code:'DEMO-CENTRAL',capacity:620,availabilityAt14:68,area:'City Centre',parkingType:'general',payment:'paid'},
  {id:'DEMO-02',name:'Market Square Parking',code:'DEMO-MARKET',capacity:420,availabilityAt14:46,area:'Market District',parkingType:'general',payment:'free'},
  {id:'DEMO-03',name:'Riverside Car Park',code:'DEMO-RIVER',capacity:310,availabilityAt14:23,area:'Riverside',parkingType:'permit',payment:'paid'},
  {id:'DEMO-04',name:'North Quarter Garage',code:'DEMO-NORTH',capacity:780,availabilityAt14:57,area:'North Quarter',parkingType:'reserved',payment:'paid'},
  {id:'DEMO-05',name:'West End Parking',code:'DEMO-WEST',capacity:260,availabilityAt14:16,area:'West End',parkingType:'general',payment:'paid'}
];

// parkingType and payment values above are DEMO ONLY; Chris should map these to real database fields.
