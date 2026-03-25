## tsurvey.nim -- SURVEY pattern integration tests.

{.experimental: "strict_funcs".}

import std/[unittest, os]
import basis/code/choice
import hydra/[survey]

when not declared(survey_port):
  const survey_port = 41040

var g_surveyor: SpSurveyor

proc surveyor_thread() {.thread.} =
  {.gcsafe.}:
    g_surveyor = new_surveyor(2000)
    discard g_surveyor.listen(survey_port)
    discard g_surveyor.accept()

suite "SURVEY":
  test "single respondent":
    var t: Thread[void]
    createThread(t, surveyor_thread)
    sleep(200)

    let resp = new_respondent()
    let cr = resp.connect("127.0.0.1", survey_port)
    check cr.is_good
    sleep(100)

    # Respondent thread: recv question, send reply
    proc responder() {.thread.} =
      {.gcsafe.}:
        let r = resp.recv()
        if r.is_good:
          discard resp.respond("answer:" & r.val)

    var rt: Thread[void]
    createThread(rt, responder)

    let sr = g_surveyor.survey("question?")
    check sr.is_good
    check sr.val.len >= 1
    check sr.val[0] == "answer:question?"

    joinThread(rt)
    close(resp)
    joinThread(t)
    close(g_surveyor)
