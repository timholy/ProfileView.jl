# This functionality is currently broken (looking for volunteers to fix it)

(Once fixed it can move back to the README)

- The toolbar at the top contains two icons to load and save profile
  data, respectively.  Clicking the save icon will prompt you for a
  filename.  Launching `ProfileView.view(nothing)` opens a blank
  window; you can populate it with saved data by clicking on the
  "open" icon.

### Saving profile data manually

  If you're using the Gtk backend, the easiest approach is to click on
  the "Save as" icon.

  From the REPL, you can save profile data for later viewing and analysis using the JLD file format.
  The main trick is that the backtrace data, on its own, is only valid within a particular
  julia session. To become portable, you have to save "line information" that looks
  up the particular line number in the source code corresponding to a particular
  machine instruction. Here's an example:

  ```julia
  li, lidict = Profile.retrieve()
  using JLD
  @save "/tmp/foo.jlprof" li lidict
  ```
  Now open a new julia session, and try the following:
  ```
  using HDF5, JLD, ProfileView
  @load "/tmp/foo.jlprof"
  ProfileView.view(li, lidict=lidict)
  ```
