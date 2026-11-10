// Works out the name this copy of the app reports, so you can tell copies
// apart when there is more than one.
//
// ECS gives every task a metadata endpoint, and puts its address in the
// ECS_CONTAINER_METADATA_URI_V4 environment variable. The endpoint's /task
// path returns details about the task, including its ARN. The last part of
// the ARN is the task ID, which is the ID the ECS console shows for the task.
//
// Outside ECS the variable isn't set, so the app uses INSTANCE_NAME instead.
export async function getInstanceName() {
  const fallback = process.env.INSTANCE_NAME || "local";
  const metadataUri = process.env.ECS_CONTAINER_METADATA_URI_V4;

  if (!metadataUri) {
    return fallback;
  }

  try {
    const res = await fetch(`${metadataUri}/task`);
    const task = await res.json();

    return task.TaskARN.split("/").pop();
  } catch (error) {
    console.error("Could not read the task ID from ECS metadata", error);
    return fallback;
  }
}
